#!/bin/bash
set -e
set -o xtrace

input=$1
output=$2
image_tag=$3

## Configuration
image_name="nf-batch-tag"           # container image name
aws_profile="my-profile"            # from `~/.aws/credentials
aws_region="eu-west-1"              # AWS region
aws_queue="nf-batch-tag-job-queue"  # AWS batch queue
aws_s3_bucket="s3://nf-batch-tag/working"  # S3 bucket
aws_container_registry="111111111111.dkr.ecr.${aws_region}.amazonaws.com"

## Create an image
docker pull "nextflow/bash"
FULLNAME="${aws_container_registry}/${image_name}"
TAG="${FULLNAME}:${image_tag}"
docker tag "nextflow/bash" "${TAG}"

## Push the image to ECR
aws ecr create-repository --profile "${aws_profile}" --repository-name "${image_name}" || echo "Couldn't create registry, assume it exists"
aws ecr get-login-password --profile "${aws_profile}" --region "${aws_region}" | docker login --username AWS --password-stdin "${aws_container_registry}"
docker push "${TAG}"

## Run nextflow
AWS_PROFILE="${aws_profile}" nextflow run main.nf \
    -profile awsbatch -w "${aws_s3_bucket}" \
    --aws_image_tag "${image_tag}" --aws_queue "${aws_queue}" \
    --aws_image "${FULLNAME}" \
    --aws_region "${aws_region}" \
    --output "${output}_${image_tag}" --input "${input}"
