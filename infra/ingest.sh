#!/usr/bin/env bash
# Deploys the ingest Lambda (public job boards -> S3 raw landing). Safe to re-run.
# Pass "run" to invoke it after deploying, or a JSON payload to scope the run:
#   infra/ingest.sh
#   infra/ingest.sh run
#   infra/ingest.sh '{"sources":["remoteok"]}'
#
# Unlike the loader, dbt and api functions this one is NOT in the VPC: the VPC has no internet
# gateway and no NAT, so a Lambda inside it cannot reach Greenhouse or any other board. It only
# needs S3 PutObject, which it gets over the public endpoint with the policy below.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"
cd "$(dirname "$0")/.."
source infra/lambda_lib.sh

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
FUNCTION=datatrace-ingest
ROLE=datatrace-ingest-lambda
HANDLER=datatrace.lambda_handler.handler
ZIP=dist/ingest.zip
# 60+ boards fetched in sequence with retries; a slow board should not fail the run.
# Matches the deployed function: a full run is around four minutes.
TIMEOUT=600
MEMORY=512
ENV="Variables={DATATRACE_OUT=s3://datatrace-raw-${ACCOUNT_ID}-${AWS_REGION}/raw}"

infra/build_lambda.sh ingest >/dev/null

role_arn=$(ensure_role "$ROLE" infra/iam_ingest_policy.json)

if aws lambda get-function --function-name "$FUNCTION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNCTION" --zip-file "fileb://$ZIP" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION"
  aws lambda update-function-configuration --function-name "$FUNCTION" \
    --environment "$ENV" --timeout "$TIMEOUT" --memory-size "$MEMORY" >/dev/null
else
  for _ in $(seq 10); do
    if aws lambda create-function --function-name "$FUNCTION" \
      --runtime python3.13 --architectures arm64 --handler "$HANDLER" \
      --role "$role_arn" --zip-file "fileb://$ZIP" \
      --timeout "$TIMEOUT" --memory-size "$MEMORY" --environment "$ENV" \
      --tags project=datatrace >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
fi
aws lambda wait function-updated --function-name "$FUNCTION"

case "${1-}" in
  "") ;;
  run) invoke_lambda ;;
  *)   invoke_lambda "$1" ;;
esac
