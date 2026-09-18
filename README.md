# DataTrace

A job market analytics pipeline that pulls postings from public job board APIs, lands them in S3, models them in Postgres with dbt, and surfaces trends in Tableau.

Python ingestion → AWS Lambda (EventBridge) → S3 → RDS Postgres → dbt → Tableau Public

Sources: Greenhouse, Lever, RemoteOK public APIs. Scope: US postings only (filtered in dbt staging).

## AWS setup

The account is on the AWS (new) free plan, where work happens in a project
account (264350941264) reached through a login session, not IAM user keys. An
AWS-managed SCP limits the account to **us-east-2**: Lambda, Scheduler, RDS and
S3 bucket creation are denied in every other region.

    aws login --profile datatrace
    export AWS_PROFILE=datatrace AWS_REGION=us-east-2

`infra/s3_raw_bucket.sh` creates and configures `datatrace-raw-<account>-<region>`.
Ingest to S3 with:

    uv run datatrace-ingest --out s3://datatrace-raw-264350941264-us-east-2/raw

`botocore[crt]` is a dev dependency because boto3 needs it to read `aws login`
credentials; Lambda uses its execution role instead.

## Lambda

`datatrace.lambda_handler.handler` wraps the same `run()` as the CLI. It reads
`DATATRACE_OUT` for the destination and accepts an optional
`{"sources": [...]}` event for test invokes. Build the arm64 / python3.13 zip
(requests + the package + `config/boards.toml`, about 650K) with:

    infra/build_lambda.sh

The function `datatrace-ingest` (us-east-2, python3.13 arm64, 512 MB, 5 min
timeout, async retries 0) runs as `datatrace-ingest-lambda`, which can only put
objects under `raw/` and write its own log group. Deploy a new build with:

    aws lambda update-function-code --function-name datatrace-ingest --zip-file fileb://dist/ingest.zip

A full run takes about 45s and peaks under 200 MB.
