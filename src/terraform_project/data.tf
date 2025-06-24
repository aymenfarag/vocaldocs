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

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# Archive files for Lambda functions
data "archive_file" "codebuild_invoker_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/codebuild_invoker"
  output_path = "${path.module}/../lambda_functions/codebuild_invoker.zip"
}

data "archive_file" "image_converter_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/image_converter"
  output_path = "${path.module}/../lambda_functions/image_converter.zip"
}

data "archive_file" "polly_invoker_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/polly_invoker"
  output_path = "${path.module}/../lambda_functions/polly_invoker.zip"
}

data "archive_file" "upload_execution_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/upload_execution"
  output_path = "${path.module}/../lambda_functions/upload_execution.zip"
}

data "archive_file" "track_execution_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/track_execution"
  output_path = "${path.module}/../lambda_functions/track_execution.zip"
}