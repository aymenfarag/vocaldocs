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

AWS Lambda function for converting text to speech using Amazon Polly.

This module processes text files stored in S3, converts them to speech using Amazon Polly,
and saves the resulting audio files back to S3. It handles large text by splitting it into
chunks, processing each chunk separately, and optionally combining the results.

The function is triggered by S3 events when new text files are uploaded.
"""

import json
import logging
import os
import time
from typing import List

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
polly = boto3.client("polly")
dynamodb = boto3.resource("dynamodb")

TABLE = dynamodb.Table(os.environ["DYNAMODB_TABLE"])


MAX_CHARS = 190000  # Safe limit below 200,000 characters


def lambda_handler(event: dict, _) -> dict:
    """
    AWS Lambda function handler for converting text to speech.

    This function is triggered by S3 events when new text files are uploaded.
    It performs the following operations:
    1. Extracts the text content from the S3 object
    2. Retrieves the language setting from DynamoDB
    3. Splits the text into manageable chunks if necessary
    4. Converts each chunk to speech using Amazon Polly
    5. Combines multiple audio files if needed
    6. Updates the task status in DynamoDB

    Args:
        event (dict): The event data from the S3 trigger
        _: Unused Lambda context parameter

    Returns:
        dict: A response object with statusCode and body containing information
              about the processing result
    """
    logger.info("Received event: %s", json.dumps(event, indent=2))

    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = event["Records"][0]["s3"]["object"]["key"]

    logger.info("Processing file: s3://%s/%s", bucket, key)

    try:
        reference_key = key.split("/")[1]

        language = get_language_from_dynamodb(reference_key)

        response = s3.get_object(Bucket=bucket, Key=key)
        text_content = response["Body"].read().decode("utf-8")

        # Split text into chunks if necessary
        text_chunks = split_text(text_content)

        audio_files: List[str] = []
        for i, chunk in enumerate(text_chunks):
            task_id = start_polly_task(bucket, reference_key, chunk, i, language)
            audio_file = wait_for_polly_task(task_id)
            audio_files.append(audio_file)

        if len(audio_files) > 1:
            # Combine audio files if there are multiple chunks
            combined_audio_key = combine_audio_files(bucket, reference_key, audio_files)
            final_audio_key = rename_to_audio_mp3(
                bucket, combined_audio_key, reference_key
            )
            logger.info(
                "Combined audio file saved and renamed: s3://%s/%s",
                bucket,
                final_audio_key,
            )
        else:
            final_audio_key = rename_to_audio_mp3(
                bucket, f"download/{reference_key}/{audio_files[0]}", reference_key
            )
            logger.info(
                "Single audio file renamed: s3://%s/%s", bucket, final_audio_key
            )

        update_dynamodb_status(reference_key, "Voice-is-Ready")

        return {
            "statusCode": 200,
            "body": json.dumps("Processing completed successfully"),
        }

    except Exception as e:
        logger.error("Error processing file %s: %s", key, e)
        update_dynamodb_status(reference_key, "failed")
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error processing file: {str(e)}"),
        }


def get_language_from_dynamodb(reference_key: str) -> str:
    """
    Retrieve the language setting for a task from DynamoDB.

    Args:
        reference_key (str): The unique identifier for the task.

    Returns:
        str: The language setting (e.g., 'english', 'arabic') in lowercase.

    Raises:
        ClientError: If there's an error retrieving data from DynamoDB.
    """
    try:
        response = TABLE.get_item(Key={"reference_key": reference_key})
        language = str(response["Item"]["Language"]).lower()
        return language
    except ClientError as e:
        logger.error("Error retrieving language from DynamoDB: %s", e)
        raise


def split_text(text: str) -> List[str]:
    """
    Split a large text into smaller chunks that fit within Amazon Polly's character limit.

    This function splits text by words to ensure that no chunk exceeds the maximum
    character limit defined by MAX_CHARS.

    Args:
        text (str): The input text to be split.

    Returns:
        List[str]: A list of text chunks, each within the size limit.
    """
    words = text.split()
    chunks: List[str] = []
    current_chunk = []

    for word in words:
        if len(" ".join(current_chunk + [word])) <= MAX_CHARS:
            current_chunk.append(word)
        else:
            chunks.append(" ".join(current_chunk))
            current_chunk = [word]

    if current_chunk:
        chunks.append(" ".join(current_chunk))

    return chunks


def start_polly_task(
    bucket: str, reference_key: str, text: str, chunk_index: int, language: str
) -> str:
    """
    Start an asynchronous Amazon Polly speech synthesis task.

    Args:
        bucket (str): The S3 bucket where the audio file will be saved.
        reference_key (str): The unique identifier for the task.
        text (str): The text to convert to speech.
        chunk_index (int): The index of the current text chunk.
        language (str): The language of the text.

    Returns:
        str: The task ID of the Polly synthesis task.

    Raises:
        ClientError: If there's an error with Polly service.
        ValueError: If text is empty or language is not supported.
    """
    if not text.strip():
        logger.error("Cannot start Polly task: empty text provided")
        raise ValueError("Empty text provided for speech synthesis")

    try:
        output_prefix = f"download/{reference_key}/chunk_{chunk_index}_"

        logger.info(
            "Starting Polly task for chunk %d with %d characters",
            chunk_index,
            len(text),
        )

        response = polly.start_speech_synthesis_task(
            OutputFormat="mp3",
            OutputS3BucketName=bucket,
            OutputS3KeyPrefix=output_prefix,
            Text=text,
            VoiceId=get_voice_id(language),
            LanguageCode=get_language_code(language),
        )

        task_id = response["SynthesisTask"]["TaskId"]
        logger.info("Successfully started Polly task: %s", task_id)
        return task_id

    except ClientError as e:
        logger.error("Failed to start Polly synthesis task: %s", e)
        logger.error("Error for chunk %d with language %s", chunk_index, language)
        raise


def get_voice_id(language: str) -> str:
    """
    Get the appropriate Amazon Polly voice ID for a given language.

    Args:
        language (str): The language for which to get a voice ID.

    Returns:
        str: The Amazon Polly voice ID.

    Raises:
        ValueError: If the language is not supported.
    """
    if language == "english":
        return "Joanna"
    elif language == "arabic":
        return "Zeina"
    else:
        raise ValueError(f"Unsupported language: {language}")


def get_language_code(language: str) -> str:
    """
    Get the appropriate language code for Amazon Polly based on the language name.

    Args:
        language (str): The language name (e.g., 'english', 'arabic').

    Returns:
        str: The language code for Amazon Polly (e.g., 'en-US', 'arb').

    Raises:
        ValueError: If the language is not supported.
    """
    if language == "english":
        return "en-US"
    elif language == "arabic":
        return "arb"
    else:
        raise ValueError(f"Unsupported language: {language}")


def wait_for_polly_task(task_id: str) -> str:
    """
    Wait for an Amazon Polly speech synthesis task to complete.

    This function polls the status of a Polly task until it completes,
    fails, or times out.

    Args:
        task_id (str): The ID of the Polly synthesis task.

    Returns:
        str: The filename of the generated audio file.

    Raises:
        Exception: If the task fails or times out.
    """
    start_time = time.time()
    end_time = start_time + 300  # seconds

    while time.time() < end_time:
        task_status = polly.get_speech_synthesis_task(TaskId=task_id)
        status = task_status["SynthesisTask"]["TaskStatus"]

        if status == "completed":
            logger.info("Speech synthesis task completed: %s", task_id)
            return task_status["SynthesisTask"]["OutputUri"].split("/")[-1]
        elif status == "failed":
            logger.error("Speech synthesis task failed: %s", task_id)
            raise Exception(f"Speech synthesis task failed: {task_id}")

        time.sleep(5)

    logger.error("Speech synthesis task timed out: %s", task_id)
    raise Exception(f"Speech synthesis task timed out: {task_id}")


def rename_to_audio_mp3(bucket: str, source_key: str, reference_key: str) -> str:
    """
    Rename an S3 object to a standardized audio filename.

    This function copies the source object to a new location with the name 'Audio.mp3'
    and then deletes the original object.

    Args:
        bucket (str): The S3 bucket containing the object.
        source_key (str): The key of the source object.
        reference_key (str): The unique identifier for the task.

    Returns:
        str: The key of the renamed object.

    Raises:
        ClientError: If there's an error with S3 operations.
    """
    destination_key = f"download/{reference_key}/Audio.mp3"
    try:
        s3.copy_object(
            Bucket=bucket,
            CopySource={"Bucket": bucket, "Key": source_key},
            Key=destination_key,
        )
        logger.info(
            "Successfully copied S3 object from %s to %s", source_key, destination_key
        )

        s3.delete_object(Bucket=bucket, Key=source_key)
        logger.info("Successfully deleted original S3 object: %s", source_key)

        return destination_key
    except ClientError as e:
        logger.error("S3 operation failed during rename: %s", e)
        logger.error(
            "Failed to rename %s to %s in bucket %s",
            source_key,
            destination_key,
            bucket,
        )
        raise


def combine_audio_files(bucket: str, reference_key: str, audio_files: List[str]) -> str:
    """
    Create a manifest file listing all audio chunks for later processing.

    This function creates a text file in S3 that contains the filenames of all
    audio chunks that need to be combined.

    Args:
        bucket (str): The S3 bucket where the manifest will be saved.
        reference_key (str): The unique identifier for the task.
        audio_files (List[str]): List of audio filenames to be combined.

    Returns:
        str: The S3 key of the created manifest file.

    Raises:
        ClientError: If there's an error with S3 operations.
        ValueError: If audio_files list is empty.
    """
    if not audio_files:
        logger.error("Cannot create manifest: audio_files list is empty")
        raise ValueError("No audio files provided for combining")

    combined_key = f"download/{reference_key}/combined_audio_info.txt"
    content = "\n".join(audio_files)

    try:
        s3.put_object(Bucket=bucket, Key=combined_key, Body=content)
        logger.info(
            "Successfully created manifest file at %s with %d audio files",
            combined_key,
            len(audio_files),
        )
        return combined_key
    except ClientError as e:
        logger.error("Failed to create manifest file in S3: %s", e)
        logger.error("Could not write to s3://%s/%s", bucket, combined_key)
        raise


def update_dynamodb_status(reference_key: str, status: str) -> None:
    """
    Update the status of a processing task in DynamoDB.

    Args:
        reference_key (str): The unique identifier for the task.
        status (str): The new status to set for the task.

    Returns:
        None
    """
    try:
        response = TABLE.update_item(
            Key={"reference_key": reference_key},
            UpdateExpression="SET TaskStatus = :status",
            ExpressionAttributeValues={":status": status},
        )
        logger.info("DynamoDB update response: %s", json.dumps(response, default=str))
    except ClientError as e:
        logger.error("Error updating DynamoDB: %s", e)
