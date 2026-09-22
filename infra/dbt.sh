#!/usr/bin/env bash
# Builds the dbt container image, pushes it to ECR and deploys/invokes the dbt Lambda.
# Safe to re-run. ECR storage for one image is a few cents a month.
#   infra/dbt.sh                              # dbt build
#   infra/dbt.sh '{"command":["test"]}'       # any command in dbt_handler.ALLOWED
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"
cd "$(dirname "$0")/.."
source infra/lambda_lib.sh

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REPO=datatrace-dbt
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPO}:latest"

FUNCTION=datatrace-dbt
ROLE=datatrace-dbt-lambda
SG_NAME=datatrace-pipeline-lambda
POLICY_FILE=infra/iam_dbt_policy.json
TIMEOUT=900
MEMORY=2048
ENV="Variables={DB_HOST=$(rds_endpoint),DB_USER=datatrace_pipeline}"

if ! aws ecr describe-repositories --repository-names "$REPO" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "$REPO" \
    --image-scanning-configuration scanOnPush=true --tags Key=project,Value=datatrace >/dev/null
  # Keep one image: every push otherwise adds ~1 GB of billed storage
  aws ecr put-lifecycle-policy --repository-name "$REPO" --lifecycle-policy-text \
    '{"rules":[{"rulePriority":1,"description":"keep the last 2 images","selection":
      {"tagStatus":"any","countType":"imageCountMoreThan","countNumber":2},
      "action":{"type":"expire"}}]}' >/dev/null
fi

uv export --only-group lambda-dbt --no-hashes --format requirements.txt -q -o build/requirements-dbt.txt
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
# Lambda rejects the OCI image index buildx produces by default: it wants one platform manifest,
# with no provenance or SBOM attestations alongside it
docker build --platform linux/arm64 --provenance=false --sbom=false \
  -f infra/dbt.Dockerfile -t "$IMAGE" -q . >/dev/null
docker push -q "$IMAGE" >/dev/null

if aws lambda get-function --function-name "$FUNCTION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNCTION" --image-uri "$IMAGE" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION"
  aws lambda update-function-configuration --function-name "$FUNCTION" \
    --environment "$ENV" --timeout "$TIMEOUT" --memory-size "$MEMORY" >/dev/null
else
  role_arn=$(ensure_role "$ROLE" "$POLICY_FILE")
  for _ in $(seq 10); do
    if aws lambda create-function --function-name "$FUNCTION" \
      --package-type Image --code "ImageUri=$IMAGE" --architectures arm64 \
      --role "$role_arn" --timeout "$TIMEOUT" --memory-size "$MEMORY" --environment "$ENV" \
      --vpc-config "SubnetIds=$(private_subnets),SecurityGroupIds=$(security_group "$SG_NAME")" \
      --tags project=datatrace >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
fi
aws lambda wait function-updated --function-name "$FUNCTION"
invoke_lambda "${1-}"
