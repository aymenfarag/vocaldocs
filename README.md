# Project VocalDocs

VocalDocs is a solution that converts PDF documents into audio files using Serverless Event Driven Architecture on AWS. This repository contains all the necessary code and Terraform infrastructure as code (IaC) to deploy the solution.

## Architecture
![Architecture Diagram](./images/architecture.jpg)

## Repository HL Structure
**CodeBuild Artifacts**: Contains the necessary files to build the Docker image for the PDFSplitter Lambda function

**Lambda Functions**: Contains the deployment packages for all Lambda functions used in the solution

**Static Website**: Contains the frontend files for the user interface

**Terraform Project**: Contains all IaC files to deploy the required AWS resources

## Repository Detailed Structure
```plaintext
vocaldocs repo
├── images
│   ├── architecture.jpg
├── README.md
└── project vocaldocs
    ├── CodeBuild_Artifacts
    │   ├── Dockerfile
    │   ├── lambda_function
    │   └── requirements
    ├── Lambda_Function
    │   ├── ImageConverter.zip
    │   ├── PollyInvoker.zip
    │   ├── upload-execution.zip
    │   └── track-execution.zip
    ├── Static Website
    │   ├── index.html
    │   ├── script.js
    │   └── style.css
    └── Terraform Project
        ├── main.tf
        ├── outputs.tf
        ├── terraform.tfvars
        └── variables.tf
```
       
## Prerequisites

Before deploying this solution, ensure you have:

1. AWS CLI installed and configured with appropriate credentials
2. Terraform installed (version 0.12 or later)
3. Amazon Bedrock LLM (Claude 3.5 Sonnet v1.0) enabled in your target AWS region
4. Amazon Polly service available with required languages in your target region
5. Git installed on your local machine

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/aymenfarag/vocaldocs.git
cd vocaldocs
```
Deploy the Infrastructure

Navigate to the Terraform project directory:
```bash
cd "project vocaldocs/Terraform Project"
```

Initialize Terraform:
```bash
terraform init
```

Review the planned changes:
```bash
terraform plan
```

Apply the infrastructure:
```bash
terraform apply
```

### Lambda Functions
1. **upload-execution**

    Frontend

    Part of New Request Function static website flow

    Invocation: From static website Javascript with Cognito

    Goal: This lambda function will upload the pdf document to S3 bucket under prefix upload/ then will save the metadata to a Dynamo_db table

    Deployment: As part of Terraform deployment, you deploy the lambda .zip file
2. **track-execution**

    Frontend

    Part of Track Existing Request Function static website flow

    Invocation: From static website Javascript with Cognito

    Goal: This lambda function will check the Dynamo_db table and retrieve all the ready voice for all uploaded documents by that user and it will create a pre-signed url for the user

    Deployment: As part of Terraform deployment, you deploy the lambda .zip file
3. **PDFSplitter-CONTAINER**

    Backend 

    Part of New Request Function static website flow 

    Invocation: From Dynamo DB Stream "If New Raw Added" 

    Goal: PDF to Image conversion 

    Deployment: As part of Terraform deployment, you deploy CodeBuild artifact to build the image that will be used to run this lambda function
4. **ImageConverter**

    Backend 

    Part of New Request Function static website flow 

    Invocation: From SNS Integration with Topic:Images-Text-BedrockInvoker

    Goal: Initiate API call with LLM model to convert each image to a clear text 

    Deployment: As part of Terraform deployment, you deploy the lambda .zip file
5. **PollyInvoker**

    Backend 

    Part of New Request Function static website flow 

    Invocation: From S3 event notification if there is new .txt file is uploaded to S3 bucket under prefix download/

    Goal: Initiate API call with Polly to read the final text file into the selected language

    Deployment: As part of Terraform deployment, you deploy the lambda .zip file


**Feel free to submit issues and enhancement requests!**

Contact [aymanahmad@gmail.com & walid.ahmed.shehata@gmail.com]
License [Specify your license here]

## Architecture Details & Flow

# VocalDocs

VocalDocs is a serverless application that converts PDF documents to audio files using AWS services.

## Architecture Details & Flow

VocalDocs is built using a serverless architecture on AWS, leveraging several key services:

### Frontend Hosting
- **Amazon S3**: Hosts the static website files (HTML, JavaScript, and CSS).
- **Amazon CloudFront**: Serves as a Content Delivery Network (CDN) for the website, improving performance and security.
  - Configured with Origin Access Control (OAC) to ensure the S3 bucket is not directly accessible.

### Authentication
- **Amazon Cognito User Pools**: Manages user authentication and authorization.

### Backend Services
- **Amazon S3**: Stores uploaded documents and processed files.
- **Amazon DynamoDB**: Stores metadata about submitted jobs.
- **AWS Lambda**: Processes documents and manages workflow.
- **Amazon SNS**: Facilitates communication between Lambda functions.
- **Amazon Bedrock**: Provides AI capabilities for text extraction.
- **Amazon Polly**: Converts text to speech.

## User Flow

1. Users access the website through the CloudFront distribution URL.
2. Before accessing any features, users must authenticate using Cognito User Pools.
3. Once authenticated, users can:
   - Submit new TTS requests
   - Track existing requests they've previously submitted

### Submitting a New Request
1. User navigates to the `new-request.html` page.
2. User uploads a PDF file (max 5MB).
3. User selects the document language (currently English or Arabic).
4. User specifies the starting and ending page ranges.
5. User submits the request.

### Backend Processing
1. The document is uploaded to an S3 bucket.
2. A new record is created in DynamoDB with job details and S3 object location.
3. DynamoDB Streams trigger a Lambda function (PDF Splitter) when new records are inserted.
4. PDF Splitter:
   - Retrieves the document from S3
   - Splits the PDF into individual pages
   - Extracts the specified page range
   - Converts pages to images
   - Publishes a message to an SNS topic upon completion
5. A second Lambda function (Images-to-Text) is triggered by the SNS message.
6. Images-to-Text:
   - Processes images sequentially
   - Sends each image to Amazon Bedrock (Claude Sonnet 3.5 v1) for text extraction
   - Concatenates extracted text from all pages
   - Writes the formatted text file back to S3
7. S3 event notification triggers the third Lambda function (Text-to-Voice) when a new .txt file is created.
8. Text-to-Voice:
   - Retrieves the formatted text file from S3
   - Passes the text to Amazon Polly for text-to-speech conversion
   - Writes the resulting audio file back to S3
   - Updates the DynamoDB record to indicate "Voice-is-ready"

### Tracking Requests
1. User navigates to the `track-requests.html` page.
2. This triggers a Lambda function to fetch records from DynamoDB for the authenticated user.
3. The function returns the status of all jobs submitted by the user.
4. If a job is complete (Voice-is-ready), the user is presented with an option to play the audio file.

## Data Management
- DynamoDB table has TTL enabled, deleting records after 1 week.
- DynamoDB Streams are configured with a filter to trigger Lambda only on new record insertions.

## Security

- The S3 bucket is not directly accessible to users. All requests are routed through CloudFront.
- CloudFront is configured with Origin Access Control (OAC) to securely access the S3 bucket.
- User authentication is required before accessing any service features.

## Future Enhancements
- Support for additional document formats beyond PDF.
- Expansion of supported languages for document processing.

## Troubleshooting Steps 

In case of any issues, you can check developer tools logs, aws cloudwatch logs for all the components in the solution to troubleshoot the issue

Also, there are some quick checkpoints that can help you debug the flow and figure out where it has been stopped, check those checkpoints:

- document-request-bucket prefix upload/ : If the document upload is completed successfully, you should find a new uploaded object in this prefix under the reference_key, also you should find a new entry in the Dynamo Database Table : Document_Request_db
- document-request-bucket prefix images/ : If PDF to Image conversion flow (by lambda: PDFSplitter-CONTAINER) is completed successfully, you should find the images exist in this prefix under the reference_key
- document-request-bucket prefix download/ : If the Image to Text conversion flow (by lambda: ImageConverter) is completed successfully, you should find the output text in this prefix under the reference_key 
- document-request-bucket prefix download/ : If the Text to Voice conversion flow (by lambda: PollyInvoker) is completed successfully, you should find the final audio file in this prefix under the reference key 

