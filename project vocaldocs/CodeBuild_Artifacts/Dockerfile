FROM public.ecr.aws/lambda/python:3.11

# Install system dependencies
RUN yum install -y gcc zlib-devel libjpeg-devel poppler-utils

# Set working directory
WORKDIR /var/task

# Copy requirements file
COPY requirements.txt .

# Install Python packages
RUN pip install -r requirements.txt

# Copy lambda function code
COPY lambda_function.py .

# Set permissions
RUN chmod 644 lambda_function.py

CMD [ "lambda_function.lambda_handler" ]
