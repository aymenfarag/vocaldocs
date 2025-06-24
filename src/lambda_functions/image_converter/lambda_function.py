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

AWS Lambda function for converting images to text using Amazon Bedrock.

This module processes images stored in S3, extracts text content using Amazon Bedrock's
Claude model, and saves the extracted text back to S3. It uses DynamoDB to track the
status of processing tasks.

The function is triggered by SNS notifications when new images are ready for processing.
"""

import base64
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime")
dynamodb = boto3.resource("dynamodb")


def get_model_endpoint() -> str:
    """
    Determine the appropriate Bedrock model endpoint based on the AWS region.

    Returns:
        str: The region-specific Claude model endpoint identifier.

    Raises:
        ValueError: If the current region is not supported.
    """
    region = os.environ["AWS_REGION"]
    if region.startswith("eu-"):
        return "eu.anthropic.claude-3-5-sonnet-20240620-v1:0"
    elif region.startswith("us-"):
        return "us.anthropic.claude-3-5-sonnet-20240620-v1:0"
    elif region.startswith("ap-"):
        return "apac.anthropic.claude-3-5-sonnet-20240620-v1:0"
    else:
        raise ValueError(f"Unsupported region: {region}")


MODEL_ENDPOINT = get_model_endpoint()


def update_dynamodb(reference_key: str, status: str) -> None:
    """
    Update the status of a processing task in DynamoDB.

    Args:
        reference_key (str): The unique identifier for the processing task.
        status (str): The new status to set for the task.

    Returns:
        None
    """
        
    try:
        table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])
        table.update_item(
            Key={"reference_key": reference_key},
            UpdateExpression="SET TaskStatus = :status",
            ExpressionAttributeValues={":status": status},
        )
        logger.info("Successfully updated status for reference_key '%s' to '%s'", reference_key, status)
    except KeyError as e:
        logger.error("Missing environment variable: %s", str(e))
        logger.error("Failed to update DynamoDB status: DYNAMODB_TABLE environment variable not set")
        raise
    except Exception as e:
        logger.error("Failed to update DynamoDB status for reference_key '%s': %s", reference_key, str(e))
        raise

def process_image_claude(image_base64: str) -> str:
    """
    Extract text from an image using Amazon Bedrock's Claude model.

    This function sends a base64-encoded image to Claude and requests
    the model to extract text content from the image.

    Args:
        image_base64 (str): Base64-encoded image data.

    Returns:
        str: The extracted text from the image.
    """
    try:
        logger.info("Sending image to Bedrock (size: %d bytes)", len(image_base64))
        
        response = bedrock.invoke_model(
            modelId=MODEL_ENDPOINT,
            body=json.dumps(
                {
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 1000,
                    "temperature": 0.0,
                    "top_p": 1.0,
                    "top_k": 0,
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "image",
                                    "source": {
                                        "type": "base64",
                                        "media_type": "image/png",
                                        "data": image_base64,
                                    },
                                },
                                {
                                    "type": "text",
                                    "text": (
                                        "Read the text in this image in sequence, DO NOT add any "
                                        "word that is not included, ignore footers and headers. Give "
                                        "me the text directly without any extra word from your side."
                                    ),
                                },
                            ],
                        }
                    ],
                }
            ),
        )
        
        response_body = json.loads(response["body"].read())
        extracted_text = response_body["content"][0]["text"]
        logger.info("Successfully extracted text from image (%d characters)", len(extracted_text))
        return extracted_text
        
    except KeyError as e:
        logger.error("Unexpected response format from Bedrock: %s", str(e))
        raise Exception(f"Failed to parse Bedrock response: {str(e)}")
    except Exception as e:
        logger.error("Error calling Bedrock service: %s", str(e))
        raise


def lambda_handler(event: dict, _) -> dict:
    """
    AWS Lambda function handler for processing images and extracting text.

    This function is triggered by SNS notifications when new images are ready for processing.
    It performs the following operations:
    1. Extracts task information from the SNS event
    2. Lists all images in the S3 bucket with the specified prefix
    3. Processes each image using Claude to extract text
    4. Combines all extracted text into a single document
    5. Uploads the combined text to S3
    6. Updates the task status in DynamoDB

    Args:
        event (dict): The event data from the SNS trigger
        _: Unused Lambda context parameter

    Returns:
        dict: A response object with statusCode and body containing information
              about the processing result
    """
    logger.info("Lambda function started")
    try:
        message = json.loads(event["Records"][0]["Sns"]["Message"])
        reference_key = message["reference_key"]
        bucket = message["bucket"]

        logger.info(
            "Processing images for reference_key: %s in bucket: %s",
            reference_key,
            bucket,
        )
        logger.info("Using model endpoint: %s", MODEL_ENDPOINT)

        all_objects = []
        paginator = s3.get_paginator("list_objects_v2")
        page_iterator = paginator.paginate(
            Bucket=bucket, Prefix=f"images/{reference_key}/"
        )

        for page in page_iterator:
            if "Contents" in page:
                all_objects.extend(page["Contents"])

        if not all_objects:
            logger.warning(
                "No images found in bucket: %s with prefix: images/%s/",
                bucket,
                reference_key,
            )
            update_dynamodb(reference_key, "pdf-to-images is failed")
            return {"statusCode": 200, "body": json.dumps("No images found to process")}

        all_text_claude = ""

        for obj in sorted(all_objects, key=lambda x: x["Key"]):
            image_key = obj["Key"]
            logger.info("Processing image: %s", image_key)

            try:
                image_object = s3.get_object(Bucket=bucket, Key=image_key)
                image_content = image_object["Body"].read()
                image_base64 = base64.b64encode(image_content).decode("utf-8")

                logger.info("Calling Claude API for image: %s", image_key)
                all_text_claude += process_image_claude(image_base64) + "\n\n"

                logger.info("Successfully processed image: %s", image_key)
            except Exception as e:
                logger.error("Error processing image %s: %s", image_key, str(e))

        # Save Claude output to S3
        claude_output_key = f"download/{reference_key}/formatted_output.txt"
        s3.put_object(Bucket=bucket, Key=claude_output_key, Body=all_text_claude)
        logger.info("Saved Claude output to S3: %s", claude_output_key)

        update_dynamodb(reference_key, "images-to-text conversion is completed")
        return {
            "statusCode": 200,
            "body": json.dumps("Images processed and text generated successfully!"),
        }
    except Exception as e:
        logger.error("Error in lambda_handler: %s", str(e))
        update_dynamodb(reference_key, "images-to-text conversion is failed")
        raise
