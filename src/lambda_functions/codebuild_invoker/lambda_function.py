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

AWS Lambda function for triggering and monitoring AWS CodeBuild projects.

This module provides functionality to start CodeBuild projects and monitor their
execution with automatic retry capability. It's designed to replace Terraform's
local-exec provisioner for more reliable and platform-independent build processes.

Environment Variables:
    - PROJECT_NAME: Optional fallback for the CodeBuild project name if not provided in the event
"""

import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codebuild_client = boto3.client("codebuild")


def lambda_handler(event: dict, _) -> dict:
    """
    Lambda function to trigger and monitor a CodeBuild project build.
    This replaces the local-exec provisioner in Terraform to make the build process
    platform-independent.

    Arguments:
        event: AWS Lambda event object containing the project name
        context: AWS Lambda context

    Returns:
        Dictionary with build status and details
    """

    project_name = event.get("project_name") or os.environ.get("PROJECT_NAME")

    if not project_name:
        return {"statusCode": 400, "body": "Missing required parameter: project_name"}

    try:
        response = codebuild_client.start_build(projectName=project_name)
        build_id = response["build"]["id"]
        logger.info("Started build with ID: %s", build_id)
    except ClientError as e:
        logger.error("Error starting build: %s", e)
        return {"statusCode": 500, "body": f"Failed to start build: {str(e)}"}

    max_attempts = 3
    attempt = 1
    success = False

    while attempt <= max_attempts:
        logger.info("Build attempt %d of %d...", attempt, max_attempts)

        build_successful = monitor_build(build_id)

        if build_successful:
            logger.info("Build completed successfully on attempt %d!", attempt)
            success = True
            break
        else:
            logger.error("Build failed on attempt %d", attempt)

            # If we haven't reached max attempts yet, try again
            if attempt < max_attempts:
                logger.info("Waiting 30 seconds before next build attempt...")
                time.sleep(30)

                # Start another build
                try:
                    response = codebuild_client.start_build(projectName=project_name)
                    build_id = response["build"]["id"]
                    logger.info("Started new build with ID: %s", build_id)
                except ClientError as e:
                    logger.error("Error starting build: %s", e)
                    # Continue with next attempt even if this fails

        attempt += 1

    if not success:
        logger.error(
            "Failed to complete build successfully after %d attempts", max_attempts
        )
        return {
            "statusCode": 500,
            "body": f"Failed to complete build successfully after {max_attempts} attempts",
        }

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "buildId": build_id,
                "status": "SUCCESS",
                "message": f"Build completed successfully on attempt {attempt}",
            }
        ),
    }


def monitor_build(build_id: str) -> bool:
    """
    Monitor the status of a CodeBuild project build

    Arguments:
        build_id: The ID of the build to monitor

    Returns:
        Boolean indicating if the build was successful
    """
    while True:
        time.sleep(10)

        try:
            response = codebuild_client.batch_get_builds(ids=[build_id])
            build = response["builds"][0]
            status = build["buildStatus"]

            logger.info("Current build status: %s", status)

            if status != "IN_PROGRESS":
                return status == "SUCCEEDED"

        except ClientError as e:
            logger.error("Error checking build status: %s", e)
            return False
