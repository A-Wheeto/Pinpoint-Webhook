# Pinpoint to HiBob Integration

A serverless integration that automatically creates employee records in HiBob when candidates are hired in Pinpoint.

## Overview

This AWS Lambda function listens for `application_hired` webhook events from Pinpoint and performs the following actions:

1. Receives the webhook notification when an applicant is moved to "hired" stage
2. Fetches complete applicant data from Pinpoint API
3. Creates a new employee record in HiBob with relevant information
4. Uploads the candidate's CV to their HiBob profile (if available)
5. Adds a comment on the Pinpoint application with the HiBob employee ID

## Architecture

The integration uses:
- AWS Lambda for serverless execution
- AWS API Gateway to expose the webhook endpoint
- Ruby for the implementation language
- Pinpoint API for applicant data
- HiBob API for employee creation

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

The integration provides detailed error responses:

- 400 Bad Request: Invalid JSON or event type
- 500 Internal Server Error: API failures or other unexpected errors

All errors include the request ID for tracing purposes.

## Logging

The Lambda function logs detailed information about each step of the process using AWS CloudWatch. You can review these logs in the CloudWatch console.

## Security Considerations

- API keys are stored as environment variables in Lambda, not in the code
- HTTPS is used for all API communications
- API Gateway can be configured with additional security if needed (e.g., API keys, IAM authentication)
  
