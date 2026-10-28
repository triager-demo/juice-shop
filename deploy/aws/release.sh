#!/usr/bin/env bash
set -euo pipefail

image_uri="${1:?Usage: release.sh ECR_IMAGE_URI_AT_DIGEST}"
platform_stack="${PLATFORM_STACK:-juice-shop-demo-platform}"
service_stack="${SERVICE_STACK:-juice-shop-demo-service}"
aws_region="${AWS_REGION:-us-east-2}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
platform_outputs="$(aws cloudformation describe-stacks --stack-name "$platform_stack" --region "$aws_region" --query 'Stacks[0].Outputs' --output json)"

output() {
  jq -er --arg key "$1" '.[] | select(.OutputKey == $key) | .OutputValue' <<< "$platform_outputs"
}

repository_uri="$(output RepositoryUri)"
if [[ "$image_uri" != "$repository_uri"@sha256:* ]]; then
  echo 'Release image must be a digest in this deployment’s ECR repository.' >&2
  exit 1
fi
image_digest="${image_uri##*@}"
if [[ ! "$image_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo 'Invalid SHA-256 image digest.' >&2
  exit 1
fi

aws cloudformation deploy \
  --region "$aws_region" \
  --stack-name "$service_stack" \
  --template-file "$script_dir/service.yml" \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "ImageUri=$image_uri" \
    "ClusterName=$(output ClusterName)" \
    "Subnets=$(output Subnets)" \
    "TaskSecurityGroup=$(output TaskSecurityGroup)" \
    "TargetGroupArn=$(output TargetGroupArn)" \
    "ExecutionRoleArn=$(output ExecutionRoleArn)" \
    "LogGroupName=$(output LogGroupName)"

actual_image="$(aws cloudformation describe-stacks --region "$aws_region" --stack-name "$service_stack" --query "Stacks[0].Outputs[?OutputKey=='ImageUri'].OutputValue | [0]" --output text)"
if [[ "$actual_image" != "$image_uri" ]]; then
  echo 'Deployment did not retain the requested image; check stack rollback events.' >&2
  exit 1
fi

aws ecs wait services-stable --region "$aws_region" --cluster "$(output ClusterName)" --services "$service_stack"
curl --fail --silent --show-error --retry 12 --retry-delay 5 --retry-all-errors \
  https://juice-shop.stuartmehrens.com/rest/products/search |
  jq -e '.status == "success" and (.data | length > 0)' >/dev/null
echo "Verified release: $image_uri"
