# Project VocalDocs

VocalDocs is a solution that converts PDF documents into audio files using Serverless Event Driven Architecture on AWS. This repository contains all the necessary code and Terraform infrastructure as code (IaC) to deploy the solution.

## Architecture
![Architecture Diagram](./images/architecture.jpg)

vocaldocs/ ├── images/ │ └── architecture.jpg ├── README.md └── project vocaldocs/ ├── CodeBuild_Artifacts/ │ ├── Dockerfile │ ├── lambda_function │ └── requirements ├── Lambda_Function/ │ ├── ImageConverter.zip │ ├── PollyInvoker.zip │ ├── upload-execution.zip │ └── track-execution.zip ├── Static Website/ │ ├── index.html │ ├── script.js │ └── style.css └── Terraform Project/ ├── main.tf ├── outputs.tf ├── terraform.tfvars └── variables.tf

## Repository Structure
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

## Prerequisites

Before deploying this solution, ensure you have:

1. AWS CLI installed and configured with appropriate credentials
2. Terraform installed (version 0.12 or later)
3. Amazon Bedrock LLM enabled in your target AWS region
4. Amazon Polly service available with required languages in your target region
5. Git installed on your local machine

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/aymenfarag/vocaldocs.git
cd vocaldocs
Deploy the Infrastructure

Navigate to the Terraform project directory:
cd "project vocaldocs/Terraform Project"

Initialize Terraform:
terraform init

Review the planned changes:
terraform plan

Apply the infrastructure:
terraform apply

Components

CodeBuild Artifacts: Contains the necessary files to build the Docker image for the PDFSplitter Lambda function
Lambda Functions: Contains the deployment packages for all Lambda functions used in the solution
Static Website: Contains the frontend files for the user interface
Terraform Project: Contains all IaC files to deploy the required AWS resources
Contributing

Feel free to submit issues and enhancement requests!

License

[Specify your license here]

Contact

[Your contact information or how to reach out for support]


## Detailed Deployment Instructions

## Troubleshooting Steps 

## Architecture Details & Flow 


