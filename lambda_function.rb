require 'json'
require 'net/http'
require 'uri'
require 'date'
require 'logger'

PINPOINT_API_BASE_URL = 'https://developers-test.pinpointhq.com/api/v1'
HIBOB_API_BASE_URL = "https://api.hibob.com/v1"

# Initialize logger
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

def lambda_handler(event:, context:)
  request_id = context.aws_request_id
  LOGGER.info("Processing request #{request_id}")

  begin
    body_str = event['body']
    raise "Missing request body" if body_str.nil? || body_str.empty?
    
    payload = JSON.parse(body_str)
    LOGGER.info("Received event: #{payload['event']}")

    # Return a response if the event is not "application_hired"
    unless payload['event'] == 'application_hired'
      LOGGER.warn("Invalid event type: #{payload['event']}")
      return {
        statusCode: 400,
        headers: {'Content-Type': 'application/json'},
        body: JSON.generate({
          message: "Invalid event type: #{payload['event']}. Expected 'application_hired'.",
          request_id: request_id
        })
      }
    end

    # Proceed with the application if the event is "application_hired"
    application_id = payload.dig('data', 'application', 'id')
    if application_id.nil?
      raise "Missing application ID in the payload"
    end

    # Fetch application data
    LOGGER.info("Fetching application data for ID: #{application_id}")
    data = fetch_application_data(application_id)

    # Create employee in HiBob
    LOGGER.info("Creating employee in HiBob: #{data[:email]}")
    employee_create = create_employee_in_hibob(data[:first_name], data[:last_name], data[:email])
    hibob_employee_id = employee_create[:id]

    # Upload CV to HiBob if available
    if data[:cv_url] && data[:cv_file_name]
      LOGGER.info("Uploading CV for employee ID: #{hibob_employee_id}")
      upload_result = upload_cv_to_hibob(hibob_employee_id, data[:cv_url], data[:cv_file_name])
    else
      LOGGER.info("No CV available for upload")
      upload_result = nil
    end

    # Add comment to Pinpoint application
    LOGGER.info("Adding comment into Pinpoint application for id: #{hibob_employee_id}")
    comment_result = comment_on_pinpoint_application(application_id, hibob_employee_id)
    
    # Return success response
    {
      statusCode: 200,
      headers: {'Content-Type': 'application/json'},
      body: JSON.generate({
        request_id: request_id,
        application_id: application_id.to_s,
        hibob_employee_id: hibob_employee_id,
        comment_id: comment_result[:data][:id]
      })
    }
  rescue JSON::ParserError => e
    LOGGER.error("Invalid JSON in request body: #{e.message}")
    {
      statusCode: 400,
      headers: {'Content-Type': 'application/json'},
      body: JSON.generate({
        message: "Invalid JSON in request body",
        error: e.message,
        request_id: request_id
      })
    }
  rescue StandardError => e
    LOGGER.error("Error processing request: #{e.class} - #{e.message}")
    LOGGER.error(e.backtrace.join("\n"))
    {
      statusCode: 500,
      headers: {'Content-Type': 'application/json'},
      body: JSON.generate({
        message: "Internal server error",
        error: e.message,
        request_id: request_id
      })
    }
  end
end

# Fetches application data from Pinpoint API
def fetch_application_data(application_id)
  uri = URI("#{PINPOINT_API_BASE_URL}/applications/#{application_id}?extra_fields[applications]=attachments")
  request = Net::HTTP::Get.new(uri)
  request['x-api-key'] = ENV["PINPOINT_API_KEY"]
  request['Content-Type'] = 'application/json'

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    raise "Failed to fetch application: #{response.code} - #{response.body}"
  end

  data = JSON.parse(response.body)

  attributes = data.dig("data", "attributes")

  if attributes.nil?
    raise "Invalid response format from Pinpoint API"
  end

  attachments = attributes["attachments"] || []
  pdf_cv = attachments.find { |a| a["context"] == "pdf_cv" }

  {
    first_name: attributes["first_name"],
    last_name: attributes["last_name"],
    email: attributes["email"],
    cv_url: pdf_cv&.dig("url"),
    cv_file_name: pdf_cv&.dig("filename")
  }
end

def create_employee_in_hibob(first_name, last_name, email)
  uri = URI("#{HIBOB_API_BASE_URL}/people")
  start_date = (Date.today + 1).to_s
  site = "New York (Demo)"

  max_attempts = 10
  attempt = 0
  base_email_local, base_email_domain = email.split('@')
  modified_email = email

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  while attempt < max_attempts
    body = {
      work: {
        site: site,
        startDate: start_date
      },
      firstName: first_name,
      surname: last_name,
      email: modified_email
    }.to_json

    request = Net::HTTP::Post.new(uri)
    request["accept"] = 'application/json'
    request["content-type"] = 'application/json'
    request["authorization"] = "Basic #{ENV["HIBOB_BASE64_TOKEN"]}"
    request.body = body

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      hibob_data = JSON.parse(response.body, symbolize_names: true)
      LOGGER.info("Created employee record in hibob. ID: #{hibob_data[:id]}")
      return hibob_data
    elsif response.code.to_i == 400 && response.body.include?('validations.email.alreadyexists')
      attempt += 1
      LOGGER.warn("Email already exists. Attempt #{attempt} — trying another email.")

      modified_email = "#{base_email_local}-#{attempt}@#{base_email_domain}"
    else
      raise "Failed to create employee in HiBob: #{response.code} - #{response.body}"
    end
  end

  raise "Exceeded max attempts to generate a unique email"
end

# Uploads a CV document to an employee's profile in HiBob
def upload_cv_to_hibob(employee_id, document_url, document_name)
  # Basic URL validation
  unless document_url =~ /\A#{URI::regexp(['http', 'https'])}\z/
    LOGGER.error("Invalid document URL format: #{document_url}")
    return { error: "Invalid document URL format" }
  end

  uri = URI("#{HIBOB_API_BASE_URL}/docs/people/#{employee_id}/shared")

  body = {
    documentName: document_name,
    documentUrl: document_url
  }.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Basic #{ENV['HIBOB_BASE64_TOKEN']}"
  request["Content-Type"] = "application/json"
  request["Accept"] = "application/json"
  request.body = body

  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    LOGGER.info("Document uploaded successfully to employee ID #{employee_id}")
    JSON.parse(response.body, symbolize_names: true)
  else
    raise "Failed to upload document to HiBob: #{response.code} - #{response.body}"
  end
end

def comment_on_pinpoint_application(application_id, hibob_employee_id)
  uri = URI("#{PINPOINT_API_BASE_URL}/comments")

  body = {
    data: {
      type: "comments",
      attributes: {
        body_text: "Record created with ID: #{hibob_employee_id}"
      },
      relationships: {
        commentable: {
          data: {
            type: "applications",
            id: application_id.to_s
          }
        }
      }
    }
  }.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri)
  request['x-api-key'] = ENV["PINPOINT_API_KEY"]
  request['Content-Type'] = 'application/vnd.api+json'
  request['Accept'] = 'application/vnd.api+json'
  request.body = body

  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    LOGGER.info("Successfully posted comment to application #{application_id}")
    JSON.parse(response.body, symbolize_names: true)
  else
    raise "Failed to post comment to Pinpoint: #{response.code} - #{response.body}"
  end
end
