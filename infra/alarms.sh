#!/usr/bin/env bash
# Email alerts for the daily ingest Lambda. Safe to re-run.
# Usage: infra/alarms.sh you@example.com
set -euo pipefail

EMAIL="$1"
REGION="${AWS_REGION:-us-east-2}"
FUNCTION=datatrace-ingest
LOG_GROUP="/aws/lambda/$FUNCTION"

TOPIC_ARN="$(aws sns create-topic --region "$REGION" --name datatrace-alerts --query TopicArn --output text)"
aws sns subscribe --region "$REGION" --topic-arn "$TOPIC_ARN" --protocol email \
  --notification-endpoint "$EMAIL" --query SubscriptionArn --output text

# Per-board failures are logged but don't fail the invocation, so count them from the logs
aws logs put-metric-filter --region "$REGION" --log-group-name "$LOG_GROUP" \
  --filter-name failed-sources --filter-pattern '"[ERROR]" "failed"' \
  --metric-transformations metricName=FailedSources,metricNamespace=DataTrace,metricValue=1

common=(--region "$REGION" --evaluation-periods 1 --alarm-actions "$TOPIC_ARN")
dims=(--namespace AWS/Lambda --dimensions "Name=FunctionName,Value=$FUNCTION")

aws cloudwatch put-metric-alarm "${common[@]}" "${dims[@]}" \
  --alarm-name datatrace-ingest-errors \
  --alarm-description "Ingest run crashed: every source failed, S3 error, or timeout" \
  --metric-name Errors --statistic Sum --period 3600 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching

# No data means no invocation, which is exactly what this alarm is for
aws cloudwatch put-metric-alarm "${common[@]}" "${dims[@]}" \
  --alarm-name datatrace-ingest-missed \
  --alarm-description "No ingest run in the last 24h: schedule disabled or cannot invoke" \
  --metric-name Invocations --statistic Sum --period 86400 \
  --threshold 1 --comparison-operator LessThanThreshold \
  --treat-missing-data breaching

aws cloudwatch put-metric-alarm "${common[@]}" \
  --namespace DataTrace --alarm-name datatrace-ingest-source-failures \
  --alarm-description "One or more boards failed; check the run manifest for which" \
  --metric-name FailedSources --statistic Sum --period 3600 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching

echo "Confirm the subscription email sent to $EMAIL or alerts will not be delivered."
