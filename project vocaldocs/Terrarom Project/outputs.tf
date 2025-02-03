output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

output "website_url" {
  description = "CloudFront distribution domain name"
  value       = "https://${aws_cloudfront_distribution.s3_distribution.domain_name}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.website_bucket.id
}

output "document_bucket_name" {
  description = "Name of the document request bucket"
  value       = aws_s3_bucket.document_bucket.id
}

output "cognito_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.client.id
}

output "cognito_domain" {
  description = "Cognito domain"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.document_request_db.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.vocaldocs_topic.arn
}

output "pdf_splitter_lambda_arn" {
  description = "ARN of the PDF Splitter Lambda"
  value       = aws_lambda_function.pdf_splitter.arn
}

output "image_converter_lambda_arn" {
  description = "ARN of the Image Converter Lambda"
  value       = aws_lambda_function.image_converter.arn
}

output "polly_invoker_lambda_arn" {
  description = "ARN of the Polly Invoker Lambda"
  value       = aws_lambda_function.polly_invoker.arn
}

output "upload_lambda_arn" {
  description = "ARN of the upload execution lambda function"
  value       = aws_lambda_function.upload_execution.arn
}

output "track_lambda_arn" {
  description = "ARN of the track execution lambda function"
  value       = aws_lambda_function.track_execution.arn
}


output "authenticated_role_arn" {
  description = "ARN of the authenticated user role"
  value       = aws_iam_role.authenticated.arn
}


# Add these to your existing outputs.tf file

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.pdf_lambda.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.pdf_lambda.name
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.pdf_lambda.name
}

output "build_artifacts_bucket" {
  description = "Name of the S3 bucket storing build artifacts"
  value       = aws_s3_bucket.build_artifacts.id
}

output "config_js_path" {
  value = abspath("${path.module}/../Static Website/config.js")
}

output "website_files" {
  value = concat(
    [for file in aws_s3_object.static_files : file.key],
    [aws_s3_object.config_js.key]
  )
  description = "List of files uploaded to S3 website bucket"
}

output "cognito_hosted_ui_domain" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
  description = "Cognito hosted UI domain with managed login branding"
}