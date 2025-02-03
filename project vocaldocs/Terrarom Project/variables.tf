variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
}

variable "user_pool_client_name" {
  description = "Name of the Cognito User Pool Client"
  type        = string
}

variable "app_name" {
  description = "Name of the application"
  type        = string
  default     = "VocalDocs"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito domain"
  type        = string
}

variable "document_bucket_name" {
  description = "Name of the document request bucket"
  type        = string
  default     = "document-request-bucket-vocaldocs"
}

variable "upload_lambda_name" {
  description = "Name of the upload execution lambda function"
  type        = string
  default     = "upload-execution"
}

variable "track_lambda_name" {
  description = "Name of the track execution lambda function"
  type        = string
  default     = "track-execution"
}

variable "identity_pool_name" {
  description = "Name of the Cognito Identity Pool"
  type        = string
  default     = "vocaldocs_identity_pool"
}

variable "sns_topic_name" {
  description = "Name of the SNS topic"
  type        = string
  default     = "VocalDocs-SNS-Topic"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
  default     = "Document_Request_db"
}

# Add these to your existing variables.tf file

variable "build_timeout" {
  description = "Build timeout in minutes"
  type        = number
  default     = 30
}

variable "build_compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "build_image" {
  description = "CodeBuild container image"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
}

variable "build_privileged_mode" {
  description = "Enable privileged mode for Docker builds"
  type        = bool
  default     = true
}