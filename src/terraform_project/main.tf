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

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ECR Repository
#tfsec:ignore:aws-ecr-repository-customer-key
resource "aws_ecr_repository" "pdf_lambda" {
  name         = "pdf-lambda-${random_string.suffix.result}"
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }
  image_tag_mutability = "IMMUTABLE"
}

# CodeBuild role
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-pdf-lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.${data.aws_partition.current.dns_suffix}"
        }
      }
    ]
  })
}

# CodeBuild policy
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "codebuild-pdf-lambda-policy-${random_string.suffix.result}"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Resource = ["*"]
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
      },
      {
        Effect = "Allow"
        Resource = [
          aws_ecr_repository.pdf_lambda.arn
        ]
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken",
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.build_artifacts.arn,
          "${aws_s3_bucket.build_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# S3 bucket for build artifacts
#tfsec:ignore:aws-s3-encryption-customer-key #tfsec:ignore:aws-s3-enable-bucket-logging #tfsec:ignore:aws-s3-enable-versioning
resource "aws_s3_bucket" "build_artifacts" {
  bucket        = "codebuild-artifacts-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload build files to S3
resource "aws_s3_object" "dockerfile" {
  bucket = aws_s3_bucket.build_artifacts.id
  key    = "build/Dockerfile"
  source = "${path.module}/../codebuild_artifacts/Dockerfile"
}

resource "aws_s3_object" "lambda_function" {
  bucket = aws_s3_bucket.build_artifacts.id
  key    = "build/lambda_function.py"
  source = "${path.module}/../codebuild_artifacts/lambda_function.py"
}

resource "aws_s3_object" "requirements" {
  bucket = aws_s3_bucket.build_artifacts.id
  key    = "build/requirements.txt"
  source = "${path.module}/../codebuild_artifacts/requirements.txt"
}

# CodeBuild project
resource "aws_codebuild_project" "pdf_lambda" {
  name         = "pdf-lambda-build-${random_string.suffix.result}"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type            = "LINUX_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    privileged_mode = true

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.pdf_lambda.repository_url
    }
    environment_variable {
      name  = "SNS_TOPIC_NAME"
      value = aws_sns_topic.vocaldocs_topic.name
    }
    environment_variable {
      name  = "DYNAMODB_TABLE"
      value = aws_dynamodb_table.document_request_db.name
    }
  }

  source {
    type     = "S3"
    location = "${aws_s3_bucket.build_artifacts.id}/build/"
    buildspec = jsonencode({
      version = "0.2"
      phases = {
        pre_build = {
          commands = [
            "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.pdf_lambda.repository_url}",
          ]
        }
        build = {
          commands = [
            "docker build -t ${aws_ecr_repository.pdf_lambda.repository_url}:latest .",
          ]
        }
        post_build = {
          commands = [
            "docker push ${aws_ecr_repository.pdf_lambda.repository_url}:latest",
          ]
        }
      }
    })
  }
}

# Lambda role for the CodeBuild invoker
resource "aws_iam_role" "codebuild_invoker_role" {
  name = "codebuild-invoker-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.${data.aws_partition.current.dns_suffix}"
        }
      }
    ]
  })
}

# Policy for the CodeBuild invoker Lambda
resource "aws_iam_role_policy" "codebuild_invoker_policy" {
  name = "codebuild-invoker-policy-${random_string.suffix.result}"
  role = aws_iam_role.codebuild_invoker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
        ]
        Resource = aws_codebuild_project.pdf_lambda.arn
      }
    ]
  })
}

# Lambda function to invoke and monitor CodeBuild
resource "aws_lambda_function" "codebuild_invoker" {
  filename         = "${path.module}/../lambda_functions/codebuild_invoker.zip"
  function_name    = "codebuild-invoker-${random_string.suffix.result}"
  role             = aws_iam_role.codebuild_invoker_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  timeout          = 300
  memory_size      = 128
  source_code_hash = filebase64sha256(data.archive_file.codebuild_invoker_lambda_package.output_path)
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      PROJECT_NAME = aws_codebuild_project.pdf_lambda.name
    }
  }
}

# Invoke Lambda to trigger CodeBuild
resource "aws_lambda_invocation" "invoke_codebuild" {
  function_name = aws_lambda_function.codebuild_invoker.function_name
  input = jsonencode({
    project_name = aws_codebuild_project.pdf_lambda.name
  })

  triggers = {
    dockerfile_hash   = filemd5("${path.module}/../codebuild_artifacts/Dockerfile")
    lambda_hash       = filemd5("${path.module}/../codebuild_artifacts/lambda_function.py")
    requirements_hash = filemd5("${path.module}/../codebuild_artifacts/requirements.txt")
  }

  depends_on = [
    aws_codebuild_project.pdf_lambda,
    aws_s3_object.dockerfile,
    aws_s3_object.lambda_function,
    aws_s3_object.requirements,
    aws_lambda_function.codebuild_invoker
  ]
}

# DynamoDB table
#tfsec:ignore:aws-dynamodb-enable-recovery #tfsec:ignore:aws-dynamodb-table-customer-key
resource "aws_dynamodb_table" "document_request_db" {
  name         = "${var.dynamodb_table_name}-${random_string.suffix.result}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "reference_key"

  attribute {
    name = "reference_key"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }
  server_side_encryption {
    enabled = true
  }
}

# SNS Topic
#tfsec:ignore:aws-sns-topic-encryption-use-cmk
resource "aws_sns_topic" "vocaldocs_topic" {
  name              = "${var.sns_topic_name}-${random_string.suffix.result}"
  kms_master_key_id = "alias/aws/sns"
}

# Document Request Bucket
#tfsec:ignore:aws-s3-encryption-customer-key #tfsec:ignore:aws-s3-enable-bucket-logging #tfsec:ignore:aws-s3-enable-versioning
resource "aws_s3_bucket" "document_bucket" {
  bucket        = "${var.document_bucket_name}-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "document_bucket" {
  bucket = aws_s3_bucket.document_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for document bucket
resource "aws_s3_bucket_public_access_block" "document_bucket_access" {
  bucket = aws_s3_bucket.document_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create upload and download prefixes
resource "aws_s3_object" "upload_prefix" {
  bucket  = aws_s3_bucket.document_bucket.id
  key     = "upload/"
  content = ""
}

resource "aws_s3_object" "download_prefix" {
  bucket  = aws_s3_bucket.document_bucket.id
  key     = "download/"
  content = ""
}

# New five roles and policies for the five lambda functions
# 1. Lambda Upload Execution Role and Policy
resource "aws_iam_role" "lambda_upload_execution_role" {
  name = "lambda-upload_execution-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.${data.aws_partition.current.dns_suffix}"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_upload_execution_policy" {
  name = "lambda_upload_execution_policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda_upload_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.document_bucket.arn,
          "${aws_s3_bucket.document_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.document_request_db.arn
      }
    ]
  })
}

# 2. Lambda Track Execution Role and Policy
resource "aws_iam_role" "lambda_track_execution_role" {
  name = "lambda-track_execution-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.${data.aws_partition.current.dns_suffix}"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_track_execution_policy" {
  name = "lambda_track_execution_policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda_track_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.document_bucket.arn,
          "${aws_s3_bucket.document_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.document_request_db.arn
      }
    ]
  })
}

# 3. Lambda PDFSplitter CONTAINER Role and Policy
resource "aws_iam_role" "lambda_pdfsplitter_container_role" {
  name = "lambda-PDFSplitter-CONTAINER-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.${data.aws_partition.current.dns_suffix}"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_pdfsplitter_container_policy" {
  name = "lambda_pdfsplitter_container_policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda_pdfsplitter_container_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.document_bucket.arn,
          "${aws_s3_bucket.document_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ]
        Resource = [aws_dynamodb_table.document_request_db.arn,
          "${aws_dynamodb_table.document_request_db.arn}/stream/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:ListTopics"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish",
          "sns:Subscribe",
        ]
        Resource = aws_sns_topic.vocaldocs_topic.arn
      }
    ]
  })
}

# 4. Lambda image_converter Role and Policy
resource "aws_iam_role" "lambda_image_converter_role" {
  name = "lambda-image_converter-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.${data.aws_partition.current.dns_suffix}"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_image_converter_policy" {
  name = "lambda_image_converter_policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda_image_converter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.document_bucket.arn,
          "${aws_s3_bucket.document_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.document_request_db.arn
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:ListFoundationModels"
        ]
        Resource = "*"
      }
    ]
  })
}

# 5. Lambda polly_invoker Role and Policy
resource "aws_iam_role" "lambda_polly_invoker_role" {
  name = "lambda-polly_invoker-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.${data.aws_partition.current.dns_suffix}"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_polly_invoker_policy" {
  name = "lambda_polly_invoker_policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda_polly_invoker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.document_bucket.arn,
          "${aws_s3_bucket.document_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.document_request_db.arn
      },
      {
        Effect = "Allow"
        Action = [
          "polly:GetSpeechSynthesisTask",
          "polly:StartSpeechSynthesisTask",
        ]
        Resource = "*"
      }
    ]
  })
}

# PDFSplitter-CONTAINER Lambda
resource "aws_lambda_function" "pdf_splitter" {
  function_name = "PDFSplitter-CONTAINER-${random_string.suffix.result}"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.pdf_lambda.repository_url}:latest"
  role          = aws_iam_role.lambda_pdfsplitter_container_role.arn
  timeout       = 60
  memory_size   = 512
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.document_request_db.name
      SNS_TOPIC_NAME = aws_sns_topic.vocaldocs_topic.name
    }
  }

  depends_on = [
    aws_lambda_invocation.invoke_codebuild
  ]
}

# DynamoDB Stream trigger for PDFSplitter
resource "aws_lambda_event_source_mapping" "pdf_splitter_trigger" {
  event_source_arn  = aws_dynamodb_table.document_request_db.stream_arn
  function_name     = aws_lambda_function.pdf_splitter.arn
  starting_position = "LATEST"

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
        dynamodb = {
          NewImage = {
            TaskStatus = {
              S = ["Upload-Completed"]
            }
          }
        }
      })
    }
  }
}

# image_converter Lambda
resource "aws_lambda_function" "image_converter" {
  filename         = "${path.module}/../lambda_functions/image_converter.zip"
  function_name    = "image_converter-${random_string.suffix.result}"
  role             = aws_iam_role.lambda_image_converter_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  timeout          = 300
  memory_size      = 128
  source_code_hash = filebase64sha256(data.archive_file.image_converter_lambda_package.output_path)
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.document_request_db.name
    }
  }
}

# SNS Topic Subscription for image_converter
resource "aws_sns_topic_subscription" "image_converter" {
  topic_arn = aws_sns_topic.vocaldocs_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.image_converter.arn
}

# Lambda permission for SNS
resource "aws_lambda_permission" "sns_image_converter" {
  statement_id  = "AllowSNSInvoke-${random_string.suffix.result}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_converter.arn
  principal     = "sns.${data.aws_partition.current.dns_suffix}"
  source_arn    = aws_sns_topic.vocaldocs_topic.arn
}

# polly_invoker Lambda
resource "aws_lambda_function" "polly_invoker" {
  filename         = "${path.module}/../lambda_functions/polly_invoker.zip"
  function_name    = "polly_invoker-${random_string.suffix.result}"
  role             = aws_iam_role.lambda_polly_invoker_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  timeout          = 120
  memory_size      = 128
  source_code_hash = filebase64sha256(data.archive_file.polly_invoker_lambda_package.output_path)
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.document_request_db.name
    }
  }
}

# S3 Event notification for polly_invoker
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.document_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.polly_invoker.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "download/"
    filter_suffix       = ".txt"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Lambda permission for S3
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.polly_invoker.function_name
  principal     = "s3.${data.aws_partition.current.dns_suffix}"
  source_arn    = aws_s3_bucket.document_bucket.arn
}

# Upload and Track execution Lambdas
resource "aws_lambda_function" "upload_execution" {
  filename         = "${path.module}/../lambda_functions/upload_execution.zip"
  function_name    = "${var.upload_lambda_name}-${random_string.suffix.result}"
  role             = aws_iam_role.lambda_upload_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  timeout          = 120
  source_code_hash = filebase64sha256(data.archive_file.upload_execution_lambda_package.output_path)
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.document_request_db.name
      S3_BUCKET      = aws_s3_bucket.document_bucket.bucket
    }
  }
}

resource "aws_lambda_function" "track_execution" {
  filename         = "${path.module}/../lambda_functions/track_execution.zip"
  function_name    = "${var.track_lambda_name}-${random_string.suffix.result}"
  role             = aws_iam_role.lambda_track_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  timeout          = 120
  source_code_hash = filebase64sha256(data.archive_file.track_execution_lambda_package.output_path)
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.document_request_db.name
      S3_BUCKET      = aws_s3_bucket.document_bucket.bucket
    }
  }
}

# Website S3 bucket
#tfsec:ignore:aws-s3-encryption-customer-key #tfsec:ignore:aws-s3-enable-bucket-logging #tfsec:ignore:aws-s3-enable-versioning
resource "aws_s3_bucket" "website_bucket" {
  bucket        = "${var.bucket_name}-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket private access
resource "aws_s3_bucket_public_access_block" "website_bucket_public_access_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket website configuration
resource "aws_s3_bucket_website_configuration" "website_bucket_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# CloudFront OAC
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "S3-${var.bucket_name}-${random_string.suffix.result}"
  description                       = "Origin Access Control for S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
#tfsec:ignore:aws-cloudfront-enable-waf #tfsec:ignore:aws-cloudfront-use-secure-tls-policy #tfsec:ignore:aws-cloudfront-enable-logging
resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "S3-${var.bucket_name}"
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${var.bucket_name}"
    viewer_protocol_policy = "https-only"
    compress               = true


    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized policy ID

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# S3 bucket policy for CloudFront
resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.${data.aws_partition.current.dns_suffix}"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.user_pool_name}-${random_string.suffix.result}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 7
      max_length = 256
    }


  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Account Confirmation"
    email_message        = "Your confirmation code is {####}"
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.cognito_domain_prefix}-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# UI customization
resource "aws_cognito_user_pool_ui_customization" "main" {
  client_id    = aws_cognito_user_pool_client.client.id
  css          = <<EOF
    .background-customizable {
      background-color: #000000;
      background-size: cover;
      background-position: center;
      background-repeat: no-repeat;
    }
    .banner-customizable {
      background-color: rgba(30, 30, 30, 0.8);
      border-radius: 10px 10px 0 0;
      padding: 20px 0;
    }
    .submitButton-customizable {
      background-color: #3a3a3a;
      font-size: 14px;
      font-weight: 500;
      text-transform: uppercase;
      letter-spacing: 1px;
      border: none;
      border-radius: 30px;
      padding: 12px 24px;
      color: #ffffff;
      transition: all 0.3s ease;
    }
    .submitButton-customizable:hover {
      background-color: #4a4a4a;
      transform: translateY(-3px);
      box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2);
    }
    .errorMessage-customizable {
      color: #ff6b6b;
    }
    .inputField-customizable {
      background-color: #2a2a2a;
      border: 1px solid #4a4a4a;
      border-radius: 5px;
      color: #ffffff;
      padding: 10px;
    }
    .inputField-customizable:focus {
      border-color: #4a4a4a;
    }
    .label-customizable {
      font-weight: 500;
      color: #ffffff;
    }
    .legalText-customizable {
      color: #ffffff;
    }
    .idpDescription-customizable {
      color: #ffffff;
    }
    .idpButton-customizable {
      background-color: #3a3a3a;
      border-radius: 30px;
      color: #ffffff;
    }
    .idpButton-customizable:hover {
      background-color: #4a4a4a;
    }
  EOF
  image_file   = filebase64("${path.module}/../static_website/VocalDocs.jpg")
  user_pool_id = aws_cognito_user_pool.user_pool.id

  depends_on = [aws_cognito_user_pool_domain.main]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name = "${var.user_pool_client_name}-${random_string.suffix.result}"

  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "phone"]

  callback_urls = ["https://${aws_cloudfront_distribution.s3_distribution.domain_name}"]
  logout_urls   = ["https://${aws_cloudfront_distribution.s3_distribution.domain_name}"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  auth_session_validity = 3 # minutes
}

# Cognito Identity Pool
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name = "${var.identity_pool_name}-${random_string.suffix.result}"

  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.client.id
    provider_name           = aws_cognito_user_pool.user_pool.endpoint
    server_side_token_check = false
  }
}

# IAM role for authenticated users
resource "aws_iam_role" "authenticated" {
  name = "${var.identity_pool_name}-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.${data.aws_partition.current.dns_suffix}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.${data.aws_partition.current.dns_suffix}:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.${data.aws_partition.current.dns_suffix}:amr" = "authenticated"
          }
        }
      }
    ]
  })
}

# Add IAM policies for authenticated role
resource "aws_iam_role_policy" "authenticated_policy" {
  name = "authenticated_policy-${random_string.suffix.result}"
  role = aws_iam_role.authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CognitoPolicy"
        Effect   = "Allow"
        Action   = "cognito-idp:AdminConfirmSignUp"
        Resource = aws_cognito_user_pool.user_pool.arn
      },
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.track_execution.arn,
          aws_lambda_function.upload_execution.arn
        ]
      }
    ]
  })
}

# Attach roles to identity pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    authenticated = aws_iam_role.authenticated.arn
  }
}

# Generate config.js with dynamic values
resource "local_file" "web_config" {
  filename = "${path.module}/../static_website/config.js"
  content  = <<-EOT
    const config = {
        PARTITION_DNS_SUFFIX: "${data.aws_partition.current.dns_suffix}",
        REGION: "${var.aws_region}",
        USER_POOL_ID: "${aws_cognito_user_pool.user_pool.id}",
        COGNITO_USER_POOL_DOMAIN: "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com",
        USER_POOL_CLIENT_ID: "${aws_cognito_user_pool_client.client.id}",
        IDENTITY_POOL_ID: "${aws_cognito_identity_pool.main.id}",
        CLOUDFRONT_DOMAIN: "${aws_cloudfront_distribution.s3_distribution.domain_name}",
        UPLOAD_LAMBDA_NAME: "${aws_lambda_function.upload_execution.function_name}",
        TRACK_LAMBDA_NAME: "${aws_lambda_function.track_execution.function_name}"
    };

    export default config;
  EOT
}

# Upload static files to S3
resource "aws_s3_object" "static_files" {
  for_each = toset([
    "index.html",
    "new-request.html",
    "track-request.html",
    "comingsoon.html",
    "main.js",
    "script.js",
    "styles.css",
    "VocalDocs.png",
    "VocalDocs.jpg",
    "background.png",
    "favicon.ico"
  ])

  bucket = aws_s3_bucket.website_bucket.id
  key    = each.value
  source = "${path.module}/../static_website/${each.value}"
  content_type = lookup({
    "html" = "text/html",
    "css"  = "text/css",
    "js"   = "application/javascript",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "ico"  = "image/x-icon"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "text/plain")

  etag = filemd5("${path.module}/../static_website/${each.value}")
}

# Upload config.js separately after it's created
resource "aws_s3_object" "config_js" {
  bucket       = aws_s3_bucket.website_bucket.id
  key          = "config.js"
  content      = local_file.web_config.content # Use content directly instead of file
  content_type = "application/javascript"
  etag         = md5(local_file.web_config.content) # Calculate MD5 from content

  depends_on = [local_file.web_config]
}
