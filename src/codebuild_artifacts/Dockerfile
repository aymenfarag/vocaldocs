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

FROM public.ecr.aws/lambda/python:3.13

RUN microdnf install -y gcc zlib-devel libjpeg-turbo-devel poppler-utils && microdnf clean all

WORKDIR /var/task

COPY requirements.txt .

RUN pip install -r requirements.txt

COPY lambda_function.py .

RUN chmod 644 lambda_function.py

# semgrep: no USER other than root specified is not an issue.
# see https://docs.aws.amazon.com/lambda/latest/dg/python-image.html:
#   When you deploy a container image to Lambda, Lambda automatically defines a default Linux user 
#   with least-privileged permissions. This is different from standard Docker behavior which 
#   defaults to the root user when no USER instruction is provided.
CMD [ "lambda_function.lambda_handler" ] # nosemgrep: dockerfile.security.missing-user.missing-user
