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

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

output "website_url" {
  description = "Amazon CloudFront distribution domain name"
  value       = "https://${aws_cloudfront_distribution.s3_distribution.domain_name}"
}

output "s3_bucket_name" {
  description = "Name of the Amazon S3 bucket"
  value       = aws_s3_bucket.website_bucket.id
}

output "document_bucket_name" {
  description = "Name of the Amazon S3 document request bucket"
  value       = aws_s3_bucket.document_bucket.id
}

output "cognito_client_id" {
  description = "ID of the Amazon Cognito user pool client"
  value       = aws_cognito_user_pool_client.client.id
}

output "cognito_domain" {
  description = "Amazon Cognito domain"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_user_pool_id" {
  description = "ID of the Amazon Cognito user pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "identity_pool_id" {
  description = "ID of the Amazon Cognito identity pool"
  value       = aws_cognito_identity_pool.main.id
}

output "dynamodb_table_name" {
  description = "Name of the Amazon DynamoDB table"
  value       = aws_dynamodb_table.document_request_db.name
}

output "sns_topic_arn" {
  description = "ARN of the Amazon SNS topic"
  value       = aws_sns_topic.vocaldocs_topic.arn
}

output "pdf_splitter_lambda_arn" {
  description = "ARN of the AWS Lambda PDF Splitter function"
  value       = aws_lambda_function.pdf_splitter.arn
}

output "image_converter_lambda_arn" {
  description = "ARN of the AWS Lambda Image Converter function"
  value       = aws_lambda_function.image_converter.arn
}

output "polly_invoker_lambda_arn" {
  description = "ARN of the AWS Lambda function that invokes Amazon Polly"
  value       = aws_lambda_function.polly_invoker.arn
}

output "upload_lambda_arn" {
  description = "ARN of the AWS Lambda upload execution function"
  value       = aws_lambda_function.upload_execution.arn
}

output "track_lambda_arn" {
  description = "ARN of the AWS Lambda track execution function"
  value       = aws_lambda_function.track_execution.arn
}


output "authenticated_role_arn" {
  description = "ARN of the authenticated user role"
  value       = aws_iam_role.authenticated.arn
}


# Add these to your existing outputs.tf file

output "ecr_repository_url" {
  description = "URL of the Amazon ECR repository"
  value       = aws_ecr_repository.pdf_lambda.repository_url
}

output "ecr_repository_name" {
  description = "Name of the Amazon ECR repository"
  value       = aws_ecr_repository.pdf_lambda.name
}

output "codebuild_project_name" {
  description = "Name of the AWS CodeBuild project"
  value       = aws_codebuild_project.pdf_lambda.name
}

output "build_artifacts_bucket" {
  description = "Name of the Amazon S3 bucket storing build artifacts"
  value       = aws_s3_bucket.build_artifacts.id
}

output "config_js_path" {
  value       = abspath("${path.module}/../static_website/config.js")
  description = "Absolute path to the config.js file"
}

output "website_files" {
  value = concat(
    [for file in aws_s3_object.static_files : file.key],
    [aws_s3_object.config_js.key]
  )
  description = "List of files uploaded to Amazon S3 website bucket"
}

output "cognito_hosted_ui_domain" {
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
  description = "Amazon Cognito hosted UI domain with managed login branding"
}
