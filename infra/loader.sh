#!/usr/bin/env bash
# Deploys the loader Lambda (S3 -> raw.job_postings in RDS) and runs it. Safe to re-run.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"
cd "$(dirname "$0")/.."
source infra/lambda_lib.sh

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
FUNCTION=datatrace-load
ROLE=datatrace-load-lambda
HANDLER=datatrace.load.handler
ZIP=dist/load.zip
SG_NAME=datatrace-pipeline-lambda
POLICY_FILE=infra/iam_load_policy.json
# A full load of the backlog copies a few hundred thousand rows; steady state is one run a day
TIMEOUT=600
MEMORY=1024
# No DATABASE_URL: db.connect() signs an IAM token for datatrace_pipeline instead
ENV="Variables={DATATRACE_OUT=s3://datatrace-raw-${ACCOUNT_ID}-${AWS_REGION}/raw,DB_HOST=$(rds_endpoint),DB_USER=datatrace_pipeline}"

infra/build_lambda.sh load >/dev/null
deploy_lambda
invoke_lambda "${1-}"
