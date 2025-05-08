require 'json'
require 'net/http'
require 'uri'
require 'date'

PINPOINT_API_BASE_URL = 'https://developers-test.pinpointhq.com/api/v1'
HIBOB_API_BASE_URL = "https://api.hibob.com/v1"

def lambda_handler(event:, context:)
  body_str = event['body']
  payload = JSON.parse(body_str)

  # Return a response if the event is not "application_hired"
  unless payload['event'] == 'application_hired'
    return {
      statusCode: 400,
      body: JSON.generate({
        message: "Invalid event type: #{payload['event']}. Expected 'application_hired'."
      })
    }
  end

  # Proceed with the application if the event is "application_hired"
  application_id = payload['data']['application']['id']
  job_id = payload['data']['job']['id']

  data = fetch_application_data(application_id)
  employee_create = create_employee_in_hibob(data[:first_name], data[:last_name], data[:email])
  employee_id = employee_create[:id]
  
  {
    statusCode: 200,
    body: JSON.generate({
      first_name: data[:first_name],
      last_name: data[:last_name],
      email: data[:email],
      cv_attachment: data[:cv_attachment],
      hibob_data: employee_create
    })
  }
end

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
  attachments = data.dig("data", "attributes", "attachments")
  pdf_cv = attachments.find { |a| a["context"] == "pdf_cv" }

  {
    first_name: attributes["first_name"],
    last_name: attributes["last_name"],
    email: attributes["email"],
    cv_attachment: pdf_cv["url"]
  }
end

def create_employee_in_hibob(first_name, last_name, email)
  uri = URI("#{HIBOB_API_BASE_URL}/people")
  start_date = (Date.today + 1).to_s

  body = {
    work: {
      site: "New York (Demo)",
      startDate: start_date
    },
    firstName: first_name,
    surname: last_name,
    email: email
  }.to_json

  http = Net::HTTP.new(uri.host, uri.port)

  http.use_ssl = true

  request = Net::HTTP::Post.new(uri)
  request["accept"] = 'application/json'
  request["content-type"] = 'application/json'
  request["authorization"] = "Basic #{ENV["HIBOB_BASE64_TOKEN"]}"
  request.body = body

  response = http.request(request)

  # Check if the request was successful
  if response.is_a?(Net::HTTPSuccess)
    hibob_data = JSON.parse(response.body, symbolize_names: true)
    return hibob_data
  elsif response.code.to_i == 400 && response.body.include?('validations.email.alreadyexists')
    # Handle the case where the email already exists
    return { error: "Email already exists", email: email }
  else
    # For any other error, raise the exception
    raise "Failed to create employee in HiBob: #{response.code} - #{response.body}"
  end
end
