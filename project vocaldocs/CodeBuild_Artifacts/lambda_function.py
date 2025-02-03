import os
import json
import boto3
import tempfile
import io
from pdf2image import convert_from_path
from PIL import Image
from urllib.parse import urlparse
import traceback
ssm = boto3.client('ssm')

# Function to get parameter from SSM Parameter Store
def get_parameter(name):
    response = ssm.get_parameter(Name=name, WithDecryption=True)
    return response['Parameter']['Value']

# Get the random suffix from environment variables
random_suffix = os.environ.get('RANDOM_SUFFIX')

DYNAMODB_TABLE = get_parameter(f'/vocaldocs/dynamodbtablename-{random_suffix}')
REGION_NAME = get_parameter(f'/vocaldocs/regionname-{random_suffix}')
SNS_TOPIC_NAME = get_parameter(f'/vocaldocs/snstopicname-{random_suffix}')

print("Starting lambda function initialization...")

# Set the Poppler path
os.environ['PATH'] = f"{os.environ['PATH']}:/opt/python/poppler/Library/bin"
print(f"Set PATH environment variable: {os.environ['PATH']}")

# Initialize AWS clients
print("Initializing AWS clients...")
s3 = boto3.client('s3')
print("S3 client initialized")
sns = boto3.client('sns')
print("SNS client initialized")
dynamodb = boto3.resource('dynamodb')
print("DynamoDB resource initialized")

def parse_s3_path(s3_path):
    """Extract bucket and key from S3 path"""
    print(f"Parsing S3 path: {s3_path}")
    parsed = urlparse(s3_path)
    bucket = parsed.netloc
    key = parsed.path.lstrip('/')
    print(f"Parsed bucket: {bucket}, key: {key}")
    return bucket, key

def update_dynamodb_status(reference_key, status):
    print(f"Updating DynamoDB status for reference_key: {reference_key}")
    try:
        table = dynamodb.Table(DYNAMODB_TABLE)
        response = table.update_item(
            Key={'reference_key': reference_key},
            UpdateExpression="set TaskStatus = :s",
            ExpressionAttributeValues={':s': status},
            ReturnValues="UPDATED_NEW"
        )
        print(f"DynamoDB update successful: {response}")
    except Exception as e:
        print(f"Error updating DynamoDB: {str(e)}")
        print("Stack trace:")
        print(traceback.format_exc())

def lambda_handler(event, context):
    print("Lambda handler started")

    # Construct the SNS Topic ARN dynamically using the region and account ID from the context
    region = REGION_NAME 
    print("region is: ", region)
    account_id = context.invoked_function_arn.split(":")[4]
    topic_name = SNS_TOPIC_NAME
    topic_arn = f'arn:aws:sns:{region}:{account_id}:{topic_name}'
    print("topic_arn: ", topic_arn)

    print(f"Using SNS Topic ARN: {topic_arn}")

    try:
        # Print the entire event for debugging
        print("Received event:", json.dumps(event, indent=2))

        # Check if event contains Records
        print("Validating event structure...")
        if not event or 'Records' not in event:
            print("Invalid event structure detected")
            raise Exception(f"Invalid event structure. Event: {json.dumps(event)}")

        # Process DynamoDB Stream event
        print("Processing DynamoDB Stream event...")
        try:
            # Get the new image from DynamoDB event
            print("Extracting NewImage from DynamoDB event")
            dynamodb_item = event['Records'][0]['dynamodb']['NewImage']
            print(f"DynamoDB item: {json.dumps(dynamodb_item, indent=2)}")

            # Extract reference_key
            print("Extracting reference_key")
            reference_key = dynamodb_item['reference_key']['S']
            print(f"Extracted reference_key: {reference_key}")

            # Extract S3 path
            print("Extracting S3 path")
            s3_path = dynamodb_item['S3Path']['S']
            print(f"Extracted S3 path: {s3_path}")

            # Parse S3 path
            print("Parsing S3 path components")
            bucket, key = parse_s3_path(s3_path)
            print(f"Using bucket: {bucket}")
            print(f"Using key: {key}")

            # Get start and end pages
            print("Extracting page range")
            start_page = int(dynamodb_item['StartPage']['S'])
            end_page = int(dynamodb_item['EndPage']['S'])
            print(f"Page range: start_page={start_page}, end_page={end_page}")

        except Exception as e:
            print(f"Error processing DynamoDB event: {str(e)}")
            print("Stack trace:")
            print(traceback.format_exc())
            raise Exception(f"Failed to process DynamoDB event: {str(e)}")

        # Download the PDF file
        print("Starting PDF download from S3")
        try:
            tmp_file = tempfile.NamedTemporaryFile(delete=False)
            print(f"Created temporary file: {tmp_file.name}")

            print(f"Downloading from bucket: {bucket}, key: {key}")
            s3.download_fileobj(bucket, key, tmp_file)
            tmp_file.close()
            print(f"PDF downloaded successfully to: {tmp_file.name}")

            # Verify file size
            file_size = os.path.getsize(tmp_file.name)
            print(f"Downloaded file size: {file_size} bytes")

        except Exception as e:
            print(f"Error downloading PDF: {str(e)}")
            print("Stack trace:")
            print(traceback.format_exc())
            raise Exception(f"Failed to download PDF from S3: {str(e)}")

        # Convert PDF to images
        print("Starting PDF to image conversion")
        try:
            print(f"Converting PDF: {tmp_file.name}")
            print(f"Using page range: {start_page} to {end_page}")

            images = convert_from_path(
                tmp_file.name,
                first_page=start_page,
                last_page=end_page
            )
            print(f"Successfully converted {len(images)} pages")
            print(f"First image size: {images[0].size if images else 'No images'}")

        except Exception as e:
            print(f"Error during PDF conversion: {str(e)}")
            print("Stack trace:")
            print(traceback.format_exc())
            raise Exception(f"PDF conversion failed: {str(e)}")

        # Upload images to S3
        print("Starting image upload process")
        uploaded_images = []
        for i, image in enumerate(images):
            try:
                print(f"Processing image {i+1} of {len(images)}")

                img_byte_arr = io.BytesIO()
                print("Converting image to bytes")
                image.save(img_byte_arr, format='PNG')
                img_byte_arr = img_byte_arr.getvalue()
                print(f"Image converted to bytes, size: {len(img_byte_arr)} bytes")

                image_key = f"images/{reference_key}/page_{i+start_page}.png"
                print(f"Uploading to S3 with key: {image_key}")

                s3.put_object(
                    Bucket=bucket,
                    Key=image_key,
                    Body=img_byte_arr,
                    ContentType='image/png'
                )
                uploaded_images.append(image_key)
                print(f"Successfully uploaded image: {image_key}")

            except Exception as e:
                print(f"Error uploading image {i+start_page}: {str(e)}")
                print("Stack trace:")
                print(traceback.format_exc())
                continue

        # Update DynamoDB status to success
        update_dynamodb_status(reference_key, 'pdf-to-images conversion is completed')

        # Clean up
        print("Starting cleanup process")
        try:
            os.unlink(tmp_file.name)
            print(f"Successfully deleted temporary file: {tmp_file.name}")
        except Exception as e:
            print(f"Warning: Failed to clean up temporary file: {str(e)}")

        # Send SNS notification
        print("Preparing SNS notification")
        try:
            sns_message = {
                'reference_key': reference_key,
                'bucket': bucket,
                'images': uploaded_images
            }
            print(f"SNS message: {json.dumps(sns_message, indent=2)}")

            sns.publish(
                TopicArn=topic_arn,
                Message=json.dumps(sns_message)
            )
            print(f"SNS notification sent successfully for reference_key: {reference_key}")

        except Exception as e:
            print(f"Error sending SNS notification: {str(e)}")
            print("Stack trace:")
            print(traceback.format_exc())

        # Prepare response
        print("Preparing success response")
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'PDF processed and images uploaded successfully!',
                'reference_key': reference_key,
                'pages_processed': len(images),
                'images_uploaded': uploaded_images
            })
        }
        print(f"Final response: {json.dumps(response, indent=2)}")
        return response

    except Exception as e:
        print("Handling main exception")
        error_message = f"Error processing PDF: {str(e)}"
        print(error_message)
        print("Stack trace:")
        print(traceback.format_exc())

        # Update DynamoDB status to failure
        update_dynamodb_status(reference_key, 'pdf-to-images conversion is failed')

        # Prepare error response
        error_response = {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'reference_key': reference_key if 'reference_key' in locals() else 'unknown'
            })
        }
        print(f"Error response: {json.dumps(error_response, indent=2)}")
        return error_response

print("Lambda function initialization completed")