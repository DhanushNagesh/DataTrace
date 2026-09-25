#!/usr/bin/env bash
# Deploys the migrations Lambda into the VPC and applies infra/db_roles.sql. Safe to re-run.
# Requires infra/network.sh and infra/rds.sh to have run first.
#   infra/db_admin.sh                                    # applies db_roles.sql
#   infra/db_admin.sh '{"scripts":["check_roles.sql"]}'  # reports what the roles can do
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"
cd "$(dirname "$0")/.."
source infra/lambda_lib.sh

FUNCTION=datatrace-db-admin
ROLE=datatrace-db-admin-lambda
HANDLER=datatrace.db_admin.handler
ZIP=dist/db-admin.zip
SG_NAME=datatrace-pipeline-lambda
# check_data.sql scans raw.job_postings, which grows with every run; at 137k rows it already
# needed more than a minute. Raised so a reporting script doesn't time out as the warehouse fills.
TIMEOUT=240
MEMORY=256

# The master password reaches the function as an environment variable, encrypted at rest. It is
# the one credential that can't come from IAM: granting rds_iam needs a password login first.
# Every role it creates uses IAM tokens instead.
PASSWORD=$(aws ssm get-parameter --name /datatrace/rds/master-password --with-decryption \
  --query Parameter.Value --output text)
ENV="Variables={DATABASE_URL=postgresql://datatrace_admin:${PASSWORD}@$(rds_endpoint):5432/datatrace?sslmode=require}"

infra/build_lambda.sh db-admin >/dev/null
deploy_lambda
invoke_lambda "${1-}"
