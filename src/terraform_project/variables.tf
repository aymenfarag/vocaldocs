# MIT No Attribution
#
# Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

variable "aws_region" {
  description = "AWS region"
  type        = string
  nullable    = false
}

variable "bucket_name" {
  description = "Name of the Amazon S3 bucket"
  type        = string
  nullable    = false
}

variable "user_pool_name" {
  description = "Name of the Amazon Cognito user pool"
  type        = string
  nullable    = false
}

variable "user_pool_client_name" {
  description = "Name of the Amazon Cognito user pool client"
  type        = string
  nullable    = false
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Amazon Cognito domain"
  type        = string
  nullable    = false
}

variable "document_bucket_name" {
  description = "Name of the Amazon S3 document request bucket"
  type        = string
  default     = "document-request-bucket-vocaldocs"
}

variable "upload_lambda_name" {
  description = "Name of the AWS Lambda upload execution function"
  type        = string
  default     = "upload-execution"
}

variable "track_lambda_name" {
  description = "Name of the AWS Lambda track execution function"
  type        = string
  default     = "track-execution"
}

variable "identity_pool_name" {
  description = "Name of the Amazon Cognito identity pool"
  type        = string
  default     = "vocaldocs_identity_pool"
}

variable "sns_topic_name" {
  description = "Name of the Amazon SNS topic"
  type        = string
  default     = "VocalDocs-SNS-Topic"
}

variable "dynamodb_table_name" {
  description = "Name of the Amazon DynamoDB table"
  type        = string
  default     = "Document_Request_db"
}
