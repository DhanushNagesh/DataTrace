#!/usr/bin/env bash
# Deploys the read-only API: a VPC Lambda behind an API Gateway HTTP API. Safe to re-run.
# Usage: infra/api.sh [allowed-origin]     e.g. infra/api.sh https://datatrace.vercel.app
#
# With no origin the API sends no CORS headers, which is all a Next.js server-side fetch needs.
# Pass the site's origin once the browser itself calls the API.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"
cd "$(dirname "$0")/.."
source infra/lambda_lib.sh

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ORIGIN="${1-}"
FUNCTION=datatrace-api
ROLE=datatrace-api-lambda
HANDLER=datatrace.api.handler
ZIP=dist/api.zip
SG_NAME=datatrace-api-lambda
POLICY_FILE=infra/iam_api_policy.json
TIMEOUT=10
MEMORY=512
API_NAME=datatrace-api
ROUTES=(
  "GET /stats" "GET /postings"
  "GET /role-mix" "GET /seniority-mix" "GET /salary-by-role" "GET /time-to-close" "GET /daily-flow"
)
ENV="Variables={DB_HOST=$(rds_endpoint),DB_USER=api_reader}"

infra/build_lambda.sh api >/dev/null
deploy_lambda
FUNCTION_ARN=$(aws lambda get-function --function-name "$FUNCTION" --query Configuration.FunctionArn --output text)

API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)
if [ "$API_ID" = None ]; then
  API_ID=$(aws apigatewayv2 create-api --name "$API_NAME" --protocol-type HTTP \
    --tags project=datatrace --query ApiId --output text)
fi

# CORS is a browser rule, not access control: curl ignores it. The throttle, the read-only
# database role and the row caps are what actually protect the database.
if [ -n "$ORIGIN" ]; then
  aws apigatewayv2 update-api --api-id "$API_ID" --cors-configuration \
    "AllowOrigins=${ORIGIN},AllowMethods=GET,AllowHeaders=content-type,MaxAge=300" >/dev/null
fi

INTEGRATION_ID=$(aws apigatewayv2 get-integrations --api-id "$API_ID" \
  --query "Items[?IntegrationUri=='${FUNCTION_ARN}'].IntegrationId | [0]" --output text)
if [ "$INTEGRATION_ID" = None ]; then
  INTEGRATION_ID=$(aws apigatewayv2 create-integration --api-id "$API_ID" \
    --integration-type AWS_PROXY --integration-uri "$FUNCTION_ARN" \
    --payload-format-version 2.0 --query IntegrationId --output text)
fi

# Only these routes exist; anything else is a 404 from the Gateway and never reaches the Lambda
for route in "${ROUTES[@]}"; do
  existing=$(aws apigatewayv2 get-routes --api-id "$API_ID" \
    --query "Items[?RouteKey=='${route}'].RouteId | [0]" --output text)
  if [ "$existing" = None ]; then
    aws apigatewayv2 create-route --api-id "$API_ID" --route-key "$route" \
      --target "integrations/${INTEGRATION_ID}" >/dev/null
  fi
done

# Nothing but Vercel calls this API, and Vercel caches every response for five minutes, so the
# steady state is a few requests a minute no matter how many people are on the site. 2/sec is
# far above that and still bounds the worst case: a caller holding the throttle open all month
# is ~5M requests, around $10 of Gateway, Lambda and egress, rather than the ~$50 that 10/sec
# would have allowed. The burst covers a cold cache refilling several routes at once.
aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name '$default' >/dev/null 2>&1 ||
  aws apigatewayv2 create-stage --api-id "$API_ID" --stage-name '$default' --auto-deploy >/dev/null
aws apigatewayv2 update-stage --api-id "$API_ID" --stage-name '$default' --auto-deploy \
  --default-route-settings 'ThrottlingRateLimit=2,ThrottlingBurstLimit=10' >/dev/null

# /postings is the only route that touches a table rather than a pre-aggregated mart, and the
# only one a caller can vary with query params, so it gets a tighter cap of its own. The
# account's Lambda concurrency limit is 10 across every function, so an API flood competes with
# the daily pipeline for slots; holding this route down keeps a scraper from starving ingest.
aws apigatewayv2 update-stage --api-id "$API_ID" --stage-name '$default' \
  --route-settings 'GET /postings={ThrottlingRateLimit=1,ThrottlingBurstLimit=5}' >/dev/null

# Lambda only accepts calls from this API; the statement id makes the grant idempotent
aws lambda add-permission --function-name "$FUNCTION" --statement-id apigateway-invoke \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/*" >/dev/null 2>&1 || true

echo "https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com"
