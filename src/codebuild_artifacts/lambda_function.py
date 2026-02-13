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

AWS Lambda function for converting PDF documents to images.

This module processes PDF documents stored in S3, converts specified pages to images,
uploads the images back to S3, and sends notifications via SNS. It uses DynamoDB
to track the status of processing tasks.

The function is triggered by DynamoDB Stream events when new PDF processing tasks
are added to the DynamoDB table.
"""

import io
import json
import logging
import os
import tempfile
import traceback
from typing import List
from urllib.parse import urlparse

import boto3
from pdf2image import convert_from_path

logger = logging.getLogger()
logger.setLevel(logging.INFO)

os.environ["PATH"] = f"{os.environ['PATH']}:/opt/python/poppler/Library/bin"

s3 = boto3.client("s3")
sns = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")


def parse_s3_path(s3_path: str) -> tuple[str, str]:
    """
    Extract bucket name and object key from an S3 URI.

    Args:
        s3_path (str): The S3 URI in the format 's3://bucket-name/path/to/object'

    Returns:
        tuple[str, str]: A tuple containing the bucket name and object key
    """
    logger.info("Parsing S3 path: %s", s3_path)
    parsed = urlparse(s3_path)
    bucket = parsed.netloc
    key = parsed.path.lstrip("/")
    logger.info("Parsed bucket: %s, key: %s", bucket, key)
    return bucket, key


def update_dynamodb_status(reference_key: str, status: str) -> None:
    """
    Update the status of a processing task in DynamoDB.

    This function updates the TaskStatus attribute of an item in the DynamoDB table
    identified by the reference_key.

    Args:
        reference_key (str): The unique identifier for the processing task
        status (str): The new status to set for the task

    Returns:
        None
    """
    logger.info("Updating DynamoDB status for reference_key: %s", reference_key)
    try:
        table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])
        response = table.update_item(
            Key={"reference_key": reference_key},
            UpdateExpression="set TaskStatus = :s",
            ExpressionAttributeValues={":s": status},
            ReturnValues="UPDATED_NEW",
        )
        logger.info("DynamoDB update successful: %s", response)
    except Exception as e:
        logger.error("Error updating DynamoDB: %s", e)
        logger.error("Stack trace: %s", traceback.format_exc())


def lambda_handler(event: dict, context) -> dict:
    """
    AWS Lambda function handler for processing PDF documents.

    This function is triggered by DynamoDB Stream events when new PDF processing tasks
    are added to the DynamoDB table. It performs the following operations:
    1. Extracts task information from the DynamoDB event
    2. Downloads the PDF file from S3
    3. Converts specified pages to images using pdf2image
    4. Uploads the images back to S3
    5. Updates the task status in DynamoDB
    6. Sends a notification via SNS

    Args:
        event (dict): The event data from the DynamoDB Stream trigger
        context: The Lambda execution context object

    Returns:
        dict: A response object with statusCode and body containing information
              about the processing result
    """
    logger.info("Lambda handler started")

    account_id = context.invoked_function_arn.split(":")[4]
    topic_arn = (
        f"arn:aws:sns:{os.environ["AWS_REGION"]}:"
        f"{account_id}:{os.environ["SNS_TOPIC_NAME"]}"
    )
    logger.info("Using SNS Topic ARN: %s", topic_arn)

    try:
        logger.info("Received event: %s", json.dumps(event, indent=2))

        logger.info("Validating event structure...")
        if not event or "Records" not in event:
            logger.error("Invalid event structure detected")
            raise Exception("Invalid event structure. Event: %s", json.dumps(event))

        logger.info("Processing DynamoDB Stream event...")
        try:
            logger.info("Extracting NewImage from DynamoDB event")
            dynamodb_item = event["Records"][0]["dynamodb"]["NewImage"]
            logger.info("DynamoDB item: %s", json.dumps(dynamodb_item, indent=2))

            logger.info("Extracting reference_key")
            reference_key = dynamodb_item["reference_key"]["S"]
            logger.info("Extracted reference_key: %s", reference_key)

            logger.info("Extracting S3 path")
            s3_path = dynamodb_item["S3Path"]["S"]
            logger.info("Extracted S3 path: %s", s3_path)

            logger.info("Parsing S3 path components")
            bucket, key = parse_s3_path(s3_path)
            logger.info("Using bucket: %s", bucket)
            logger.info("Using key: %s", key)

            logger.info("Extracting page range")
            start_page = int(dynamodb_item["StartPage"]["S"])
            end_page = int(dynamodb_item["EndPage"]["S"])
            logger.info("Page range: start_page=%d, end_page=%d", start_page, end_page)

        except Exception as e:
            logger.error("Error processing DynamoDB event: %s", e)
            logger.error("Stack trace: %s", traceback.format_exc())
            raise Exception("Failed to process DynamoDB event: %s", str(e))

        logger.info("Starting PDF download from S3")
        try:
            tmp_file = tempfile.NamedTemporaryFile(delete=False)
            logger.info("Created temporary file: %s", tmp_file.name)

            logger.info("Downloading from bucket: %s, key: %s", bucket, key)
            s3.download_fileobj(bucket, key, tmp_file)
            tmp_file.close()
            logger.info("PDF downloaded successfully to: %s", tmp_file.name)

            file_size = os.path.getsize(tmp_file.name)
            logger.info("Downloaded file size: %d bytes", file_size)

        except Exception as e:
            logger.error("Error downloading PDF: %s", e)
            logger.error("Stack trace: %s", traceback.format_exc())
            raise Exception("Failed to download PDF from S3: %s", str(e))

        logger.info("Starting PDF to image conversion")
        try:
            logger.info("Converting PDF: %s", tmp_file.name)
            logger.info("Using page range: %d to %d", start_page, end_page)

            images = convert_from_path(
                tmp_file.name, first_page=start_page, last_page=end_page
            )
            logger.info("Successfully converted %d pages", len(images))
            logger.info(
                "First image size: %s", images[0].size if images else "No images"
            )

        except Exception as e:
            logger.error("Error during PDF conversion: %s", e)
            logger.error("Stack trace: %s", traceback.format_exc())
            raise Exception("PDF conversion failed: %s", str(e))

        logger.info("Starting image upload process")
        uploaded_images: List[str] = []
        for i, image in enumerate(images):
            try:
                logger.info("Processing image %d of %d", i + 1, len(images))

                img_byte_arr = io.BytesIO()
                logger.info("Converting image to bytes")
                image.save(img_byte_arr, format="PNG")
                img_byte_arr = img_byte_arr.getvalue()
                logger.info(
                    "Image converted to bytes, size: %d bytes", len(img_byte_arr)
                )

                image_key = f"images/{reference_key}/page_{i+start_page}.png"
                logger.info("Uploading to S3 with key: %s", image_key)

                s3.put_object(
                    Bucket=bucket,
                    Key=image_key,
                    Body=img_byte_arr,
                    ContentType="image/png",
                )
                uploaded_images.append(image_key)
                logger.info("Successfully uploaded image: %s", image_key)

            except Exception as e:
                logger.error("Error uploading image %d: %s", i + start_page, e)
                logger.error("Stack trace: %s", traceback.format_exc())
                continue

        update_dynamodb_status(reference_key, "pdf-to-images conversion is completed")

        logger.info("Starting cleanup process")
        try:
            os.unlink(tmp_file.name)
            logger.info("Successfully deleted temporary file: %s", tmp_file.name)
        except Exception as e:
            logger.warning("Warning: Failed to clean up temporary file: %s", e)

        logger.info("Preparing SNS notification")
        try:
            sns_message = {
                "reference_key": reference_key,
                "bucket": bucket,
                "images": uploaded_images,
            }
            logger.info("SNS message: %s", json.dumps(sns_message, indent=2))

            sns.publish(TopicArn=topic_arn, Message=json.dumps(sns_message))
            logger.info(
                "SNS notification sent successfully for reference_key: %s",
                reference_key,
            )

        except Exception as e:
            logger.error("Error sending SNS notification: %s", e)
            logger.error("Stack trace: %s", traceback.format_exc())

        logger.info("Preparing success response")
        response = {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "PDF processed and images uploaded successfully!",
                    "reference_key": reference_key,
                    "pages_processed": len(images),
                    "images_uploaded": uploaded_images,
                }
            ),
        }
        logger.info("Final response: %s", json.dumps(response, indent=2))
        return response

    except Exception as e:
        logger.error("Handling main exception")
        error_message = f"Error processing PDF: {str(e)}"
        logger.error("%s", error_message)
        logger.error("Stack trace: %s", traceback.format_exc())

        update_dynamodb_status(reference_key, "pdf-to-images conversion is failed")

        error_response = {
            "statusCode": 500,
            "body": json.dumps(
                {
                    "error": error_message,
                    "reference_key": (
                        reference_key if "reference_key" in locals() else "unknown"
                    ),
                }
            ),
        }
        logger.error("Error response: %s", json.dumps(error_response, indent=2))
        return error_response
