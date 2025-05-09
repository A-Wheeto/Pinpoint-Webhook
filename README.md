# HiBob Integration for Pinpoint Webhook

This AWS Lambda function listens for `application_hired` webhook events from [Pinpoint](https://pinpointhq.com) and performs the following:

1. Fetches application details (including the candidate’s CV) from the Pinpoint API.
2. Creates a new employee in [HiBob](https://www.hibob.com/).
3. Uploads the candidate’s CV to their HiBob profile (if available).
4. Posts a comment on the Pinpoint application with the HiBob record ID.

---

## 🧱 Tech Stack

- Ruby
- AWS Lambda
- Net::HTTP
- HiBob API
- Pinpoint API

---

## ⚙️ Environment Variables

The Lambda function relies on the following environment variables:

| Variable | Description |
|---------|-------------|
| `PINPOINT_API_KEY` | API key for authenticating with the Pinpoint API |
| `HIBOB_BASE64_TOKEN` | Base64-encoded API token for authenticating with HiBob |

---

## 🚀 Deployment

You can deploy this function as an AWS Lambda handler. Make sure the environment variables are configured either via the AWS Console or Terraform/CDK as part of your deployment pipeline.

**Handler**: `lambda_function.lambda_handler`  
**Runtime**: `ruby2.7` or newer (depending on your AWS Lambda settings)  
**Trigger**: API Gateway Webhook (configured to receive Pinpoint webhook events)

---

## 🧪 Example Event Payload

Here is a sample payload that triggers this Lambda function:

```json
{
  "event": "application_hired",
  "data": {
    "application": {
      "id": "1234567"
    }
  }
}
