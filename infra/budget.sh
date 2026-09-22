#!/usr/bin/env bash
# Monthly cost budget with email alerts. Safe to re-run. AWS Budgets is free for the first two.
# Usage: infra/budget.sh [email] [monthly-limit-usd]
set -euo pipefail

EMAIL="${1:-dhnagesh@ucdavis.edu}"
LIMIT="${2:-25}"
NAME=datatrace-monthly
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

notification() { # threshold type
  cat <<JSON
{"Notification": {"NotificationType": "$2", "ComparisonOperator": "GREATER_THAN",
  "ThresholdType": "PERCENTAGE", "Threshold": $1},
 "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "$EMAIL"}]}
JSON
}

if aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name "$NAME" >/dev/null 2>&1; then
  echo "budget $NAME already exists"
  exit 0
fi

# FORECASTED warns before the money is spent; ACTUAL is the backstop if spend jumps suddenly
aws budgets create-budget --account-id "$ACCOUNT_ID" \
  --budget "{\"BudgetName\": \"$NAME\", \"BudgetType\": \"COST\", \"TimeUnit\": \"MONTHLY\",
             \"BudgetLimit\": {\"Amount\": \"$LIMIT\", \"Unit\": \"USD\"}}" \
  --notifications-with-subscribers "[$(notification 50 ACTUAL), $(notification 100 FORECASTED)]"

echo "budget $NAME: \$$LIMIT/month, alerts to $EMAIL (confirm nothing; Budgets emails directly)"
