#!/usr/bin/env bash
# One-time setup for the raw landing bucket. Safe to re-run.
set -euo pipefail

REGION="${AWS_REGION:-$(aws configure get region)}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="datatrace-raw-${ACCOUNT_ID}-${REGION}"

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  # The AWS (new) free plan denies s3:CreateBucket from the CLI via an org SCP,
  # so the bucket itself has to be created in the console. Everything else works.
  echo "Bucket $BUCKET does not exist."
  echo "Create it in the S3 console (region $REGION, defaults are fine), then re-run."
  exit 1
fi

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Raw keys are unique per run, so versioning would only add cost. Clean up failed
# multipart uploads (they bill as storage but never show up in a listing).
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
  --lifecycle-configuration '{"Rules":[{"ID":"abort-incomplete-mpu","Status":"Enabled","Filter":{},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":1}}]}'

echo "DATATRACE_OUT=s3://${BUCKET}/raw"
