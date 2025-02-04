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

VocalDocs is built using a serverless architecture on AWS, leveraging several key services:
### Frontend Hosting
- **Amazon S3**: Hosts the static website files (HTML, JavaScript, and CSS).
- **Amazon CloudFront**: Serves as a Content Delivery Network (CDN) for the website, improving performance and security.
  - Configured with Origin Access Control (OAC) to ensure the S3 bucket is not directly accessible.

### Authentication
- **Amazon Cognito User Pools**: Manages user authentication and authorization.

## User Flow

1. Users access the website through the CloudFront distribution URL.
2. Before accessing any features, users must authenticate using Cognito User Pools.
3. Once authenticated, users can:
   - Submit new TTS requests
   - Track existing requests they've previously submitted

## Security

- The S3 bucket is not directly accessible to users. All requests are routed through CloudFront.
- CloudFront is configured with Origin Access Control (OAC) to securely access the S3 bucket.
- User authentication is required before accessing any service features.

## Troubleshooting Steps 

In case of any issues, you can check developer tools logs, aws cloudwatch logs for all the components in the solution to troubleshoot the issue

Also, there are some quick checkpoints that can help you debug the flow and figure out where it has been stopped, check those checkpoints:

- document-request-bucket prefix upload/ : If the document upload is completed successfully, you should find a new uploaded object in this prefix under the reference_key, also you should find a new entry in the Dynamo Database Table : Document_Request_db
- document-request-bucket prefix images/ : If PDF to Image conversion flow (by lambda: PDFSplitter-CONTAINER) is completed successfully, you should find the images exist in this prefix under the reference_key
- document-request-bucket prefix download/ : If the Image to Text conversion flow (by lambda: ImageConverter) is completed successfully, you should find the output text in this prefix under the reference_key 
- document-request-bucket prefix download/ : If the Text to Voice conversion flow (by lambda: PollyInvoker) is completed successfully, you should find the final audio file in this prefix under the reference key 

