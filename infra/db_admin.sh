#!/usr/bin/env bash
# Deploys the migrations Lambda into the VPC and applies infra/db_roles.sql. Safe to re-run.
# Requires infra/network.sh and infra/rds.sh to have run first.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"

FUNCTION=datatrace-db-admin
ROLE=datatrace-db-admin-lambda
cd "$(dirname "$0")/.."

infra/build_lambda.sh db-admin >/dev/null

SUBNETS=$(aws ec2 describe-subnets \
  --filters Name=tag:Name,Values=datatrace-private-a,datatrace-private-b \
  --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=datatrace-pipeline-lambda \
  --query 'SecurityGroups[0].GroupId' --output text)
ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier datatrace \
  --query 'DBInstances[0].Endpoint.Address' --output text)

if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" \
    --assume-role-policy-document file://infra/lambda_trust_policy.json >/dev/null
  # Managed policy: CloudWatch Logs plus the ENI calls every VPC Lambda needs
  aws iam attach-role-policy --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
fi
ROLE_ARN=$(aws iam get-role --role-name "$ROLE" --query Role.Arn --output text)

# The master password reaches the function as an environment variable, encrypted at rest.
# It is the one credential that can't come from IAM: granting rds_iam to a role requires a
# password login first. Every role it creates uses IAM tokens instead.
PASSWORD=$(aws ssm get-parameter --name /datatrace/rds/master-password --with-decryption \
  --query Parameter.Value --output text)
ENV="Variables={DATABASE_URL=postgresql://datatrace_admin:${PASSWORD}@${ENDPOINT}:5432/datatrace?sslmode=require}"

if aws lambda get-function --function-name "$FUNCTION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNCTION" \
    --zip-file fileb://dist/db-admin.zip >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION"
  aws lambda update-function-configuration --function-name "$FUNCTION" --environment "$ENV" >/dev/null
else
  # A new role takes a few seconds to become assumable by Lambda
  for _ in $(seq 10); do
    if aws lambda create-function --function-name "$FUNCTION" \
      --runtime python3.13 --architectures arm64 --handler datatrace.db_admin.handler \
      --role "$ROLE_ARN" --zip-file fileb://dist/db-admin.zip \
      --timeout 60 --memory-size 256 --environment "$ENV" \
      --vpc-config "SubnetIds=${SUBNETS},SecurityGroupIds=${SG}" \
      --tags project=datatrace >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
fi
aws lambda wait function-updated --function-name "$FUNCTION"

# Pass a payload to choose scripts, e.g. infra/db_admin.sh '{"scripts":["db_roles.sql"]}'
PAYLOAD="${1-}"
[ -z "$PAYLOAD" ] && PAYLOAD='{}'

OUT=$(mktemp)
aws lambda invoke --function-name "$FUNCTION" --payload "$PAYLOAD" --cli-binary-format raw-in-base64-out "$OUT" \
  --query '[StatusCode,FunctionError]' --output text
cat "$OUT"; echo
