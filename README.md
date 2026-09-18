# DataTrace

A job market analytics pipeline that pulls postings from public job board APIs, lands them in S3, models them in Postgres with dbt, and surfaces trends in Tableau.

Python ingestion → AWS Lambda (EventBridge) → S3 → RDS Postgres → dbt → Tableau Public

Sources: Greenhouse, Lever, RemoteOK public APIs. Scope: US postings only (filtered in dbt staging).

## AWS setup

The account is on the AWS (new) free plan, where work happens in a project
account (264350941264, us-east-1) reached through a login session, not IAM user
keys:

    aws login --profile datatrace
    export AWS_PROFILE=datatrace

Bucket creation is blocked from the CLI by an org policy, so create
`datatrace-raw-<account>-<region>` in the S3 console once, then run
`infra/s3_raw_bucket.sh` to apply the rest of the settings. Ingest to S3 with:

    uv run datatrace-ingest --out s3://datatrace-raw-264350941264-us-east-1/raw

`botocore[crt]` is a dev dependency because boto3 needs it to read `aws login`
credentials; Lambda uses its execution role instead.

## Lambda

`datatrace.lambda_handler.handler` wraps the same `run()` as the CLI. It reads
`DATATRACE_OUT` for the destination and accepts an optional
`{"sources": [...]}` event for test invokes. Build the arm64 / python3.13 zip
(requests + the package + `config/boards.toml`, about 650K) with:

    infra/build_lambda.sh
