# Pinpoint to HiBob Integration

A serverless integration that automatically creates employee records in HiBob when candidates are hired in Pinpoint.

## Overview

This AWS Lambda function listens for `application_hired` webhook events from Pinpoint and performs the following actions:

1. Receives the webhook notification when an applicant is moved to "hired" stage
2. Fetches complete applicant data from Pinpoint API
3. Creates a new employee record in HiBob with relevant information
4. Uploads the candidate's CV to their HiBob profile (if available)
5. Adds a comment on the Pinpoint application with the HiBob employee ID

## Design Decisions

This section outlines key decisions made during development and the reasoning behind them:

### Serverless with AWS Lambda & API Gateway

- **Why**: The integration is event-driven, triggered by hiring events in Pinpoint, making AWS Lambda a cost-effective and scalable choice.
- **How**: An API Gateway endpoint triggers the Ruby-based Lambda function upon receiving an `application_hired` webhook.
- **Alternative Considered**: A traditional server or containerised service would require additional infrastructure and cost without providing meaningful advantages for this use case.

### Centralised HTTP Timeout Handling

- **Why**: To ensure consistent and safe behavior when making external API requests.
- **How**: A `http_client_for(uri)` helper is defined to configure all `Net::HTTP` connections with an `open_timeout` of 5 seconds and a `read_timeout` of 10 seconds.
- **Benefit**: Ensures the Lambda function doesn't hang on slow responses and stays within its configured timeout. It also reduces repeated boilerplate across different HTTP calls.

### Optional CV Upload Handling

- **Why**: Not all applicants have a CV available in their application record.
- **How**: The code checks for a `cv_url` and `cv_file_name` before attempting to download and upload the document to HiBob.
- **Benefit**: Prevents errors and unnecessary requests to HiBob when no document is present, increasing the function's resilience.

### Secure Use of Credentials

- **Why**: To protect sensitive information like API tokens.
- **How**: Environment variables (`PINPOINT_API_KEY`, `HIBOB_BASE64_TOKEN`) are used and accessed securely within the function.
- **Benefit**: Keeps secrets out of source code and version control, following best practices for cloud function security.

### Standard Ruby Libraries Only

- **Why**: To minimise cold start time and compatibility issues in the Lambda environment.
- **How**: All functionality is built using standard Ruby libraries like `net/http`, `uri`, `json`, and `base64`.
- **Benefit**: Ensures the code runs smoothly on AWS Lambda with no external dependencies.

## Architecture

The integration uses:
- AWS Lambda for serverless execution
- AWS API Gateway to expose the webhook endpoint
- Ruby for the implementation language
- Pinpoint API for applicant data - [Pinpoint API](https://developers.pinpointhq.com/)
- HiBob API for employee creation - [HiBob API](https://apidocs.hibob.com/)

## Prerequisites

- AWS Account with permissions to create Lambda functions and API Gateway
- Pinpoint API key
- HiBob API credentials (service user)

## Setup

### 1. Lambda Function

1. Create a new AWS Lambda function using Ruby 3.2 runtime
2. Copy the code from [lambda_function.rb](./lambda_function.rb) into your function
3. Set environment variables for API credentials (see Environment Variables section)
4. Configure memory (recommended: 256MB) and timeout (recommended: 30 seconds)

### 2. API Gateway

1. Create a new REST API in API Gateway
2. Create a resource with POST method pointed to your Lambda function
3. Deploy the API to a stage (e.g., "prod")
4. Note the endpoint URL to configure in Pinpoint

### 3. Pinpoint Webhook Configuration

1. In your Pinpoint account, navigate to Settings > Webhooks
2. Add a new webhook with the following settings:
   - Event: `application_hired`
   - URL: Your API Gateway endpoint URL
   - Format: JSON

## Environment Variables

The Lambda function requires the following environment variables:

| Variable | Description |
|----------|-------------|
| `PINPOINT_API_KEY` | Your Pinpoint API key |
| `HIBOB_BASE64_TOKEN` | Base64 encoded credentials for HiBob API authentication |

**Note on HIBOB_BASE64_TOKEN:**
This should be a Base64 encoded string of the format `SERVICE-USER-ID:TOKEN`. For example:
```
echo -n "SERVICE-12345:ABCDEFGHIJKLMNOPQRSTUVWXYZ" | base64
```

## Testing

You can test the integration using Postman or any API testing tool:

1. Send a POST request to your webhook endpoint
2. Include the following JSON payload:

```json
{
  "event": "application_hired",
  "triggeredAt": 1614687278,
  "data": {
    "application": {
      "id": 8863880
    },
    "job": {
      "id": 1
    }
  }
}
```

### Expected Response

A successful response will have status code 200 and a body similar to:

```json
{
  "status": "success",
  "message": "Employee successfully created in HiBob",
  "request_id": "c7ebe3bc-c15b-476a-9648-1469939ab200",
  "data": {
    "pinpoint": {
      "application_id": "8863880",
      "comment_id": "5186386"
    },
    "hibob": {
      "employee_id": "3628748460116673185",
      "email": "test.account@pinpoint.dev",
      "cv_uploaded": true
    }
  },
  "timestamp": "2025-05-09T14:22:30Z"
}
```

## Error Handling

The integration implements a multi-layered error handling strategy:

### Error Classification

- **Client Errors (400/422)**: Handled via a custom `ClientError` class that captures:
  - Invalid or missing request body
  - Missing application ID
  - Invalid event types
  - Malformed document URLs
  - These errors are returned with appropriate HTTP status codes and detailed messages

- **Parsing Errors (400)**: JSON parsing failures are caught separately and returned with clear messages

- **System Errors (500)**: All other unexpected exceptions, including:
  - API communication failures
  - Authentication issues
  - Timeout errors
  - Internal processing errors

### Error Response Format

All error responses follow a consistent format:

```json
{
  "message": "Human-readable error description",
  "error": "Technical details or validation errors",
  "request_id": "UUID for request tracing"
}
```

### Logging

Comprehensive logging with appropriate log levels:
- `INFO`: Standard operation events
- `WARN`: Non-critical issues that don't prevent core functionality
- `ERROR`: Critical failures that prevent successful processing

All logs include the request ID for correlation with API responses.

## Timeouts

All outbound HTTP requests to Pinpoint and HiBob APIs use a consistent timeout strategy (5 seconds open timeout, 10 seconds read timeout by default). This helps ensure the Lambda does not hang on slow network responses.

## Logging

The Lambda function logs detailed information about each step of the process using AWS CloudWatch. You can review these logs in the CloudWatch console.

## Security Considerations

- API keys are stored as environment variables in Lambda, not in the code
- HTTPS is used for all API communications
- API Gateway can be configured with additional security if needed (e.g., API keys, IAM authentication)
  
