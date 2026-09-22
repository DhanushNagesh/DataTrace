#!/usr/bin/env bash
# Shared deploy helper, sourced by the per-function scripts in this directory.
# The caller sets: FUNCTION ROLE HANDLER ZIP SG_NAME ENV TIMEOUT MEMORY [POLICY_FILE]

private_subnets() {
  aws ec2 describe-subnets --filters Name=tag:Name,Values=datatrace-private-a,datatrace-private-b \
    --query 'Subnets[].SubnetId' --output text | tr '\t' ','
}

security_group() {
  aws ec2 describe-security-groups --filters Name=group-name,Values="$1" \
    --query 'SecurityGroups[0].GroupId' --output text
}

rds_endpoint() {
  aws rds describe-db-instances --db-instance-identifier datatrace \
    --query 'DBInstances[0].Endpoint.Address' --output text
}

ensure_role() { # role name, optional inline policy file
  if ! aws iam get-role --role-name "$1" >/dev/null 2>&1; then
    aws iam create-role --role-name "$1" \
      --assume-role-policy-document file://infra/lambda_trust_policy.json >/dev/null
    # Managed policy: CloudWatch Logs plus the ENI calls every VPC Lambda needs
    aws iam attach-role-policy --role-name "$1" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
  fi
  if [ -n "${2-}" ]; then
    aws iam put-role-policy --role-name "$1" --policy-name "$(basename "$2" .json)" \
      --policy-document "file://$2"
  fi
  aws iam get-role --role-name "$1" --query Role.Arn --output text
}

deploy_lambda() {
  local subnets sg role_arn
  subnets=$(private_subnets)
  sg=$(security_group "$SG_NAME")
  role_arn=$(ensure_role "$ROLE" "${POLICY_FILE-}")

  if aws lambda get-function --function-name "$FUNCTION" >/dev/null 2>&1; then
    aws lambda update-function-code --function-name "$FUNCTION" --zip-file "fileb://$ZIP" >/dev/null
    aws lambda wait function-updated --function-name "$FUNCTION"
    aws lambda update-function-configuration --function-name "$FUNCTION" \
      --environment "$ENV" --timeout "$TIMEOUT" --memory-size "$MEMORY" >/dev/null
  else
    # A new role takes a few seconds to become assumable by Lambda
    for _ in $(seq 10); do
      if aws lambda create-function --function-name "$FUNCTION" \
        --runtime python3.13 --architectures arm64 --handler "$HANDLER" \
        --role "$role_arn" --zip-file "fileb://$ZIP" \
        --timeout "$TIMEOUT" --memory-size "$MEMORY" --environment "$ENV" \
        --vpc-config "SubnetIds=${subnets},SecurityGroupIds=${sg}" \
        --tags project=datatrace >/dev/null 2>&1; then
        break
      fi
      sleep 3
    done
  fi
  aws lambda wait function-updated --function-name "$FUNCTION"
}

invoke_lambda() { # payload, defaulting to an empty event
  local out payload
  payload="${1-}"
  [ -z "$payload" ] && payload='{}'
  out=$(mktemp)
  # No read timeout: the CLI's 60s default retries the invoke, and a second loader run racing
  # the first is only stopped by the raw.job_postings primary key
  aws lambda invoke --function-name "$FUNCTION" --payload "$payload" --cli-read-timeout 0 \
    --cli-binary-format raw-in-base64-out "$out" --query '[StatusCode,FunctionError]' --output text
  cat "$out"
  echo
}
