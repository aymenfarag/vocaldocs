"""
MIT No Attribution

Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#####

AWS Lambda function for handling document uploads.

This module processes document uploads from users, stores the files in S3,
and creates corresponding entries in DynamoDB to track the processing status.
It handles file metadata, user information, and sets up the document for
further processing in the VocalDocs workflow.
"""

import base64
from datetime import datetime, timedelta, timezone
import json
import logging
import os
import uuid

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3_client = boto3.client("s3")


table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])


def lambda_handler(event: dict, _) -> dict:
    """
    AWS Lambda function handler for processing document uploads.

    This function handles the upload of documents to the VocalDocs system.
    It performs the following operations:
    1. Extracts document metadata and content from the event
    2. Decodes the base64-encoded file content
    3. Generates a unique reference key for the document
    4. Uploads the document to S3
    5. Creates a record in DynamoDB with metadata and processing status
    6. Sets a TTL for automatic cleanup after one week

    Args:
        event (dict): The event data containing document information and content
        _: Unused Lambda context parameter

    Returns:
        dict: A response object with statusCode and body containing confirmation
              message and reference key, or an error message
    """
    logger.info("Received event: %s", json.dumps(event, indent=2))

    try:
        # Extract information from the event
        file_name = event["fileName"]
        language = event["language"]
        start_page = event["startPage"]
        end_page = event["endPage"]
        file_content_base64 = event["fileContent"]
        username = event["username"]  # This will now be the user's email

        file_content = base64.b64decode(file_content_base64)

        # Generate a unique ID for the request
        reference_key = str(uuid.uuid4())
        logger.info("reference_key: %s", reference_key)

        s3_path = f"upload/{reference_key}/{file_name}"
        s3_client.put_object(
            Bucket=os.environ["S3_BUCKET"], Key=s3_path, Body=file_content
        )

        logger.info(
            "Uploaded file to S3 at path: s3://%s/%s", os.environ["S3_BUCKET"], s3_path
        )
        current_datetime = datetime.now(timezone.utc)
        current_datetime_iso = current_datetime.isoformat()

        # Calculate expiration time (1 week from now)
        expiration_time = current_datetime + timedelta(weeks=1)
        expiration_timestamp = int(
            expiration_time.timestamp()
        )  # Convert to Unix timestamp

        item = {
            "reference_key": reference_key,
            "FileName": file_name,
            "Language": language,
            "StartPage": start_page,
            "EndPage": end_page,
            "S3Path": f"s3://{os.environ["S3_BUCKET"]}/{s3_path}",
            "UploadDateTime": current_datetime_iso,
            "TaskStatus": "Upload-Completed",
            "Username": username,  # This will be the user's email
            "ExpiresAt": expiration_timestamp,  # Add the TTL field
        }
        table.put_item(Item=item)

        logger.info("Persisted %s in DynamoDB", reference_key)

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Your document has been submitted, it may take up to 5 minutes to complete the Job.",
                    "reference_key": reference_key,
                }
            ),
        }

    except Exception as e:
        logger.error("An error occurred: %s", e)
        return {"statusCode": 500, "body": json.dumps(f"An error occurred: {str(e)}")}
