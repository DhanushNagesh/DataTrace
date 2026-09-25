#!/usr/bin/env bash
# Email alerts for the daily pipeline. Safe to re-run.
# Usage: infra/alarms.sh [you@example.com]   (the address is only needed the first time)
set -euo pipefail

EMAIL="${1-}"
REGION="${AWS_REGION:-us-east-2}"
FUNCTION=datatrace-ingest
LOG_GROUP="/aws/lambda/$FUNCTION"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_MACHINE="arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:datatrace-pipeline"

TOPIC_ARN="$(aws sns create-topic --region "$REGION" --name datatrace-alerts --query TopicArn --output text)"
if [ -n "$EMAIL" ]; then
  aws sns subscribe --region "$REGION" --topic-arn "$TOPIC_ARN" --protocol email \
    --notification-endpoint "$EMAIL" --query SubscriptionArn --output text
fi

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

sm_metric() { # id, metric name, whether to return it
  cat <<JSON
{"Id": "$1", "ReturnData": false, "MetricStat": {"Period": 3600, "Stat": "Sum", "Metric":
  {"Namespace": "AWS/States", "MetricName": "$2",
   "Dimensions": [{"Name": "StateMachineArn", "Value": "$STATE_MACHINE"}]}}}
JSON
}

# One alarm for every way a run ends badly. A failed step already publishes to this topic from
# inside the state machine; this also catches an execution that times out or is aborted.
aws cloudwatch put-metric-alarm "${common[@]}" \
  --alarm-name datatrace-pipeline-failed \
  --alarm-description "The daily pipeline failed, timed out or was aborted" \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --metrics "[$(sm_metric failed ExecutionsFailed), $(sm_metric timedout ExecutionsTimedOut),
    $(sm_metric aborted ExecutionsAborted),
    {\"Id\": \"unsuccessful\", \"Expression\": \"failed + timedout + aborted\",
     \"Label\": \"unsuccessful executions\", \"ReturnData\": true}]"

# No data means the schedule never fired, which is the failure this alarm exists for: the
# state machine failing is loud, the state machine never starting is silent.
aws cloudwatch put-metric-alarm "${common[@]}" \
  --alarm-name datatrace-pipeline-missed \
  --alarm-description "No pipeline run in the last 24h: schedule disabled or cannot start it" \
  --namespace AWS/States --metric-name ExecutionsStarted \
  --dimensions "Name=StateMachineArn,Value=$STATE_MACHINE" \
  --statistic Sum --period 86400 \
  --threshold 1 --comparison-operator LessThanThreshold \
  --treat-missing-data breaching

# Vercel caches every API response for five minutes, so normal traffic is a few requests a
# minute however busy the site is. A sustained 2,000 an hour means something is looping against
# the API, and this fires within the hour rather than waiting on the monthly budget alert.
API_ID="$(aws apigatewayv2 get-apis --region "$REGION" \
  --query "Items[?Name=='datatrace-api'].ApiId | [0]" --output text)"
if [ "$API_ID" != None ]; then
  aws cloudwatch put-metric-alarm "${common[@]}" \
    --alarm-name datatrace-api-flood \
    --alarm-description "Unusual API request volume: a scraper or a loop, not visitors" \
    --namespace AWS/ApiGateway --metric-name Count \
    --dimensions "Name=ApiId,Value=$API_ID" \
    --statistic Sum --period 3600 \
    --threshold 2000 --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching
fi

# Superseded by datatrace-pipeline-missed: the schedule now starts the state machine, not the
# ingest function, and two alarms for one outage is just two emails.
aws cloudwatch delete-alarms --region "$REGION" --alarm-names datatrace-ingest-missed

[ -n "$EMAIL" ] && echo "Confirm the subscription email sent to $EMAIL or alerts will not be delivered."
echo "alarms: $(aws cloudwatch describe-alarms --region "$REGION" --query 'length(MetricAlarms)' --output text) total (10 are free)"
