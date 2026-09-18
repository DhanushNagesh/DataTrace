# DataTrace

A job market analytics pipeline that pulls postings from public job board APIs, lands them in S3, models them in Postgres with dbt, and surfaces trends in Tableau.

Python ingestion → AWS Lambda (EventBridge) → S3 → RDS Postgres → dbt → Tableau Public

Sources: Greenhouse, Lever, RemoteOK public APIs. Scope: US postings only (filtered in dbt staging).

## Local setup

Keep the repo out of iCloud-synced folders (`~/Documents`, `~/Desktop`). iCloud sets the
macOS `hidden` flag on dot-named files it syncs, and Python 3.13+ skips hidden `.pth`
files, so the venv's editable install silently stops importing `datatrace`. It also
syncs `.git`, which risks corrupting the repo. This repo lives in `~/code/DataTrace`.

    uv sync

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

A full run takes about 45s and peaks under 200 MB. EventBridge Scheduler
(`datatrace-ingest-daily`) invokes it at 06:00 America/Los_Angeles with no
retries, using the `datatrace-scheduler` role, which can only invoke this function.

`infra/alarms.sh <email>` sets up email alerts through the `datatrace-alerts` SNS
topic: the run errored or timed out (`datatrace-ingest-errors`), no run in 24h
(`datatrace-ingest-missed`), or any board failed (`datatrace-ingest-source-failures`,
from a log metric filter). The run manifest says which boards failed.

## Local warehouse

dbt development runs against Postgres 17 in Docker, not RDS, so iterating on
models costs nothing. RDS only comes up once the models work.

    docker compose up -d
    cp .env.example .env
    uv run datatrace-load --src data/raw
    uv run datatrace-load --src s3://datatrace-raw-264350941264-us-east-2/raw

`datatrace-load` finds run manifests that have not been loaded yet and copies
each run's records into `raw.job_postings` (one row per posting, payload as
`jsonb`) in a single transaction, then records the manifest in `raw.loaded_runs`.
Rerunning is a no-op, and a run that fails partway leaves nothing behind.
`uv run pytest` uses a separate `datatrace_test` database and skips the loader
tests when Postgres is not running.

## dbt

The dbt project lives in `dbt/`. `profiles.yml` sits next to it, with a `dev` target
pointing at the Docker Postgres and a `prod` target (RDS) that reads `DBT_HOST`,
`DBT_USER` and `DBT_PASSWORD` from the environment.

    cd dbt
    uv run dbt build              # dev
    uv run dbt build --target prod

- `staging.stg_<source>__postings` (views): one typed row per posting per ingest
  run, all countries, with an `is_us` flag.
- `staging.stg_job_postings`: the union of those, filtered to US-accessible postings:
  a US location, or remote with no region stated (`is_remote_anywhere`). This is where the US filter happens.
- `marts.postings` (table): one row per US-accessible posting with its latest attributes,
  `first_seen_at`/`last_seen_at`, and `is_active`, meaning it was seen in the latest run that
  returned its board, so a board outage doesn't mark its postings closed.

US classification: Lever has a country code. Greenhouse and RemoteOK only have
free text, so they go through the `is_us_location` macro (regex over country names,
state names/codes and major cities). `seeds/us_location_cases.csv` holds
hand-labelled locations, and `tests/assert_us_location_cases.sql` fails if the macro
gets any of them wrong. A Greenhouse posting whose location is just "Remote" or "N/A"
falls back to its `offices` list. A bare "Remote", "Worldwide", or blank RemoteOK location
counts as remote-anywhere, which is treated as US-accessible.

Lever's API has no company name; `seeds/lever_companies.csv` maps board to display
name, and a warn-level test flags Lever boards missing from it.
