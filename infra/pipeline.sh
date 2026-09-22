#!/usr/bin/env bash
# Chains the three Lambdas into one daily run and points the existing schedule at it.
# Safe to re-run. Step Functions Standard is free at this volume (~120 of 4,000 monthly
# state transitions). Pass "run" to start an execution now.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"
cd "$(dirname "$0")/.."

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
NAME=datatrace-pipeline
ROLE=datatrace-states
SCHEDULE=datatrace-ingest-daily
SM_ARN="arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:${NAME}"

DEFINITION=$(sed -e "s/REGION/${AWS_REGION}/g" -e "s/ACCOUNT/${ACCOUNT_ID}/g" infra/state_machine.json)

if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" \
    --assume-role-policy-document file://infra/states_trust_policy.json >/dev/null
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name iam_states_policy \
  --policy-document file://infra/iam_states_policy.json
ROLE_ARN=$(aws iam get-role --role-name "$ROLE" --query Role.Arn --output text)

if aws stepfunctions describe-state-machine --state-machine-arn "$SM_ARN" >/dev/null 2>&1; then
  aws stepfunctions update-state-machine --state-machine-arn "$SM_ARN" \
    --definition "$DEFINITION" --role-arn "$ROLE_ARN" >/dev/null
else
  for _ in $(seq 10); do
    if aws stepfunctions create-state-machine --name "$NAME" --definition "$DEFINITION" \
      --role-arn "$ROLE_ARN" --type STANDARD --tags key=project,value=datatrace >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
fi

# The schedule used to invoke the ingest Lambda directly; now it starts the whole chain, so
# the scheduler role needs to start executions instead of invoking that one function.
aws iam put-role-policy --role-name datatrace-scheduler --policy-name start-pipeline \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",
    \"Action\":\"states:StartExecution\",\"Resource\":\"${SM_ARN}\"}]}"

aws scheduler update-schedule --name "$SCHEDULE" \
  --schedule-expression "cron(0 6 * * ? *)" --schedule-expression-timezone America/Los_Angeles \
  --flexible-time-window Mode=OFF \
  --target "{\"Arn\":\"${SM_ARN}\",\"RoleArn\":\"arn:aws:iam::${ACCOUNT_ID}:role/datatrace-scheduler\",
             \"RetryPolicy\":{\"MaximumRetryAttempts\":0}}" >/dev/null

echo "state machine: $SM_ARN"
echo "schedule $SCHEDULE -> pipeline, 06:00 America/Los_Angeles"

if [ "${1-}" = "run" ]; then
  EXEC=$(aws stepfunctions start-execution --state-machine-arn "$SM_ARN" \
    --query executionArn --output text)
  echo "started $EXEC"
fi
