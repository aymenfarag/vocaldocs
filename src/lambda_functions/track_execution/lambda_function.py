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

AWS Lambda function for tracking execution and managing user requests.

This module provides functionality to track user requests, retrieve request status,
and generate presigned URLs for accessing processed audio files in S3.

The function supports two main operations:
1. Retrieving all requests for a specific user
2. Generating presigned URLs for downloading audio files
"""

from datetime import datetime, timezone
import json
import logging
import os
import time

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3_client = boto3.client(
    "s3", config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"})
)


def lambda_handler(event: dict, _) -> dict:
    """
    AWS Lambda function handler for tracking execution and managing user requests.

    This function serves as a router that handles two types of requests:
    1. Retrieving all requests for a specific user (when 'username' is provided)
    2. Generating presigned URLs for downloading audio files (when 'action' is 'generate_url')

    Args:
        event (dict): The event data containing request parameters
        _: Unused Lambda context parameter

    Returns:
        dict: A response object with statusCode and body containing the requested information
              or an error message
    """
    logger.info("Received event: %s", json.dumps(event, indent=2))
    logger.info(
        "Lambda execution started at: %s", datetime.now(timezone.utc).isoformat()
    )

    if "username" in event:
        logger.info("username")
        return get_user_requests(event["username"])
    elif (
        "action" in event
        and event["action"] == "generate_url"
        and "reference_key" in event
    ):
        logger.info("PresignedURL")
        return generate_presigned_url(event["reference_key"])
    else:
        return {"statusCode": 400, "body": json.dumps("Invalid request")}


def get_user_requests(username: str) -> dict:
    """
    Retrieve all requests associated with a specific user from DynamoDB.

    This function scans the DynamoDB table for items matching the provided username
    and returns a simplified list of requests with their status. It handles pagination
    to retrieve all matching items when there are more results than can be returned
    in a single response.

    Args:
        username (str): The username to search for in the DynamoDB table

    Returns:
        dict: A response object with statusCode and body containing the list of requests
              or an error message
    """
    logger.info("username: %s", username)

    table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])

    try:
        items = []
        last_evaluated_key = None

        while True:
            if last_evaluated_key:
                response = table.scan(
                    FilterExpression=boto3.dynamodb.conditions.Attr("Username").eq(
                        username
                    ),
                    ExclusiveStartKey=last_evaluated_key,
                )
            else:
                response = table.scan(
                    FilterExpression=boto3.dynamodb.conditions.Attr("Username").eq(
                        username
                    )
                )

            items.extend(response.get("Items", []))

            last_evaluated_key = response.get("LastEvaluatedKey")
            if not last_evaluated_key:
                break

        logger.info("Retrieved %d items for user %s", len(items), username)

        requests = []
        for item in items:
            request = {
                "reference_key": item["reference_key"],
                "fileName": item.get("FileName", "Unknown file"),
                "TaskStatus": (
                    "Voice-is-Ready"
                    if item.get("TaskStatus") == "Voice-is-Ready"
                    else "Work-In-Progress"
                ),
            }
            requests.append(request)
            logger.info("Request: %s", request)
        return {"statusCode": 200, "body": json.dumps({"requests": requests})}

    except ClientError as e:
        logger.error("An error occurred: %s", e)
        return {"statusCode": 500, "body": json.dumps(f"An error occurred: {str(e)}")}


def generate_presigned_url(reference_key: str) -> dict:
    """
    Generate a presigned URL for downloading an audio file from S3.

    This function creates a temporary URL that allows users to download
    the processed audio file without requiring AWS credentials. The URL
    is valid for 1 hour.

    Args:
        reference_key (str): The unique identifier for the task/request

    Returns:
        dict: A response object with statusCode, headers, and body containing
              the presigned URL and generation timestamp, or an error message
    """

    object_key = f"download/{reference_key}/Audio.mp3"

    current_time = int(time.time())
    logger.info("Current UTC timestamp: %d", current_time)
    logger.info("Current UTC time: %s", datetime.now(timezone.utc).isoformat())

    try:
        presigned_url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": os.environ["S3_BUCKET"], "Key": object_key},
            ExpiresIn=3600,  # URL expires in 1 hour
            HttpMethod="GET",
        )
        logger.info(
            "Presigned URL generated at: %s", datetime.now(timezone.utc).isoformat()
        )
        logger.info("Presigned URL: %s", presigned_url)

        return {
            "statusCode": 200,
            "headers": {
                "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
                "Pragma": "no-cache",
                "Expires": "0",
            },
            "body": json.dumps(
                {"presigned_url": presigned_url, "generated_at": current_time}
            ),
        }
    except ClientError as e:
        logger.error("Error generating presigned URL for %s: %s", reference_key, e)
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error generating URL: {str(e)}"),
        }
