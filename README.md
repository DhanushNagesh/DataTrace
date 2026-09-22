# DataTrace

A job market analytics pipeline that pulls postings from public job board APIs, lands them in S3, models them in Postgres with dbt, and surfaces trends in Tableau.

Python ingestion → AWS Lambda (EventBridge) → S3 → RDS Postgres → dbt → Tableau Public

Sources: public job board APIs from Greenhouse, Lever, Ashby, SmartRecruiters and Rippling (company
boards listed in `config/boards.toml`), plus the RemoteOK feed. Scope: US-accessible postings,
filtered in dbt staging.

SmartRecruiters and Rippling list endpoints leave out the job description, so each posting needs
its own detail request. `http.get_many` runs those 8 at a time, and a posting that 404s between
the list and detail calls is skipped. Rippling's list repeats a job once per location; the
source merges those before fetching details.

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

A full run takes about 3.5 minutes, most of it the ~2,000 SmartRecruiters detail requests. EventBridge Scheduler
(`datatrace-ingest-daily`) invokes it at 06:00 America/Los_Angeles with no
retries, using the `datatrace-scheduler` role, which can only invoke this function.

`infra/alarms.sh [email]` sets up email alerts through the `datatrace-alerts` SNS topic (the
address is only needed the first time; it is already subscribed):

- `datatrace-ingest-errors`: the ingest Lambda crashed or timed out.
- `datatrace-ingest-source-failures`: a board failed, counted from the logs by a metric filter.
  The run manifest says which.
- `datatrace-pipeline-failed`: an execution failed, timed out or was aborted, as one alarm over
  the sum of all three metrics. The state machine also publishes the failing state itself.
- `datatrace-pipeline-missed`: no execution started in 24h, treating missing data as breaching.
  A failing pipeline is loud; a pipeline that never starts is silent, and this is what catches it.

The state machine has a one-hour `TimeoutSeconds`, so a hung run ends and counts as timed out
instead of blocking the next day's. Four alarms; CloudWatch bills after ten.

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
- `marts.fct_job_postings` (table): one row per US-accessible posting with its latest attributes,
  `first_seen_at`/`last_seen_at`, `days_listed`, and `is_active`, meaning it was seen in the latest
  run that returned its board, so a board outage doesn't mark its postings closed. `is_active` is
  null for RemoteOK, whose feed is a rolling window of recent jobs rather than a list of open ones.
- `marts.dim_companies` (table): one row per company, joined on `company_key` (md5 of the
  normalized name), so the same company across sources is one row.

US classification: Lever, Ashby, SmartRecruiters and Rippling carry country fields. Greenhouse
and RemoteOK only have free text, so they go through the `is_us_location` macro (regex over country names,
state names/codes and major cities). `seeds/us_location_cases.csv` holds
hand-labelled locations, and `tests/assert_us_location_cases.sql` fails if the macro
gets any of them wrong. A Greenhouse posting whose location is just "Remote" or "N/A"
falls back to its `offices` list. A bare "Remote", "Worldwide", or blank RemoteOK location
counts as remote-anywhere, which is treated as US-accessible.

Lever and Ashby have no company name in their APIs; `seeds/board_companies.csv` maps
source and board to a display name, and a warn-level test flags boards missing from it.
Salary periods are normalised to year/month/week/day/hour by the `pay_interval` macro.
Rippling lists several tiered pay ranges per posting; staging keeps the first USD range.

## RDS

`infra/network.sh` creates the `datatrace` VPC (10.20.0.0/16), two private subnets in
us-east-2a/b, and three security groups. The VPC has **no internet gateway**, so nothing in it
can reach or be reached from the internet, which also means no NAT Gateway (~$32/mo) is needed.
`datatrace-rds` accepts port 5432 only from the `datatrace-api-lambda` and
`datatrace-pipeline-lambda` groups; rules name those groups rather than IP ranges.

`infra/rds.sh` creates the instance: `db.t4g.micro`, Postgres 17.11, 20 GB gp3 (no autoscaling),
single-AZ, encrypted, not publicly accessible, IAM auth on, 1-day backups, deletion protection on.
**It bills about $14/month until deleted.** Backups are short because the raw JSON in S3 is the
source of truth and the warehouse can be rebuilt from it. The random master password is stored
in Parameter Store (free; Secrets Manager is $0.40/mo per secret) at
`/datatrace/rds/master-password`.

## Migrations Lambda

RDS has no public address, so admin SQL can't run from a laptop. `datatrace-db-admin` sits in the
VPC and applies SQL scripts that ship in its own zip; an invoke may only name a bundled file, never
supply SQL. All scripts run in one transaction, and rows from a script's last statement come back
in the response.

    infra/db_admin.sh                                    # applies db_roles.sql
    infra/db_admin.sh '{"scripts":["check_roles.sql"]}'  # reports what api_reader can do

It connects as the master user, with the password injected as an environment variable at deploy
time. That is the one credential IAM can't replace: granting a role `rds_iam` requires a password
login first. Every role it creates uses IAM tokens instead.

## Loader Lambda

`datatrace-load` runs the same `load()` as the CLI, inside the VPC. `infra/loader.sh` builds,
deploys and invokes it; re-running is a no-op once every manifest is recorded.

It reaches S3 through the S3 **gateway** endpoint (free, added by `infra/network.sh`), which is
the only kind of endpoint RDS-adjacent work needs — gateway endpoints exist for S3 and DynamoDB
only, and a Lambda reaches RDS over the VPC with no endpoint at all. It logs in as
`datatrace_pipeline` with an IAM token that `db.connect()` signs locally, so the function holds no
database password. Its role may read `raw/` in the bucket and `rds-db:connect` as that one
database user, nothing else.

Long invokes need `--cli-read-timeout 0`: the CLI's 60s default gives up and retries, which starts
a second loader run alongside the first. The `raw.job_postings` primary key rejects the duplicate
copy and that transaction rolls back, so a race costs time, not correctness.

    infra/db_admin.sh '{"scripts":["check_load.sql"]}'   # runs and rows landed so far

## dbt Lambda

dbt-postgres is far past the 250 MB zip limit, so `datatrace-dbt` ships as a container image
(`infra/dbt.Dockerfile`, pushed to ECR by `infra/dbt.sh`; a lifecycle policy keeps the last two
images, about $0.25/month). The dbt project is baked into the image, and an invoke may only pick a
command from `dbt_handler.ALLOWED` — `run-operation` is excluded, since it would run arbitrary SQL
as the owner of every table.

    infra/dbt.sh                          # dbt build against the prod (RDS) target
    infra/dbt.sh '{"command":["test"]}'

`profiles.yml`'s prod target reads `DBT_HOST`/`DBT_USER`/`DBT_PASSWORD`; the handler fills them from
`DB_HOST`/`DB_USER` and an IAM token, so dbt logs in as `datatrace_pipeline` with no password.

Three things Lambda forces on dbt, all handled in `dbt_handler`:

- No `/dev/shm`, so POSIX semaphores fail. dbt's mp context and its `DbtThreadPool`
  (a `multiprocessing.pool.ThreadPool`) are swapped for thread locks and a `ThreadPoolExecutor`.
  dbt runs nodes in threads anyway. Both patches must happen before `dbt.cli.main` is imported.
- Only `/tmp` is writable: `DBT_LOG_PATH` and `DBT_TARGET_PATH` point there.
- Lambda rejects the OCI image index that buildx produces by default, hence
  `--provenance=false --sbom=false`.

Prod runs two threads, not four: on db.t4g.micro four parallel connections exhausted the instance's
CPU credits and later connections timed out mid-build.

## Daily pipeline

`infra/pipeline.sh` builds the `datatrace-pipeline` state machine: ingest, then load, then dbt,
each waiting for the one before it. The existing `datatrace-ingest-daily` schedule now starts the
state machine instead of invoking the ingest Lambda directly, so there is still one trigger at
06:00 America/Los_Angeles. Any step that fails publishes the execution state to the
`datatrace-alerts` topic and ends the run as failed. Step Functions Standard is free here
(~120 of the 4,000 free monthly state transitions).

    infra/pipeline.sh          # create or update, and repoint the schedule
    infra/pipeline.sh run      # start an execution now

Load and dbt retry twice; ingest retries only on Lambda service errors, since a failed board is
already handled per-source and a rerun would refetch every board. A full run takes about 4.5
minutes.

## Public API

`infra/api.sh [origin]` deploys `datatrace-api` into the VPC behind an API Gateway **HTTP API**
(not a REST API: $1 per million requests instead of $3.50, with CORS and throttling built in).

    infra/api.sh                                # no CORS headers; server-side fetches need none
    infra/api.sh https://<site>.vercel.app      # once the browser calls the API directly

    GET /stats       headline counts and the data freshness timestamp
    GET /postings    open postings, filtered by q, role_family, work_mode; limit/offset

The Lambda logs in as `api_reader` with an IAM token, in the `datatrace-api-lambda` security
group, which may only open connections to Postgres. Its IAM policy allows `rds-db:connect` as
that one database user and nothing else.

Routing lives in the Gateway: only the two routes above exist, so anything else is a 404 that never
reaches the Lambda. The stage throttles at 10 requests/second with a burst of 20, and responses
carry `cache-control: max-age=300` since the data changes once a day. CORS is a browser rule, not
access control — `curl` ignores it — so the real protections are the throttle, the read-only role,
bound parameters and the caps on `limit`, `offset` and `q`.

## API role

The public API connects as `api_reader`, which can read `marts` and nothing else. Create it once
per database (it is safe to rerun), before the first `dbt build`:

    docker compose exec -T postgres psql -U datatrace -d datatrace -v ON_ERROR_STOP=1 < infra/db_roles.sql

The script only creates the role and its session defaults: read-only transactions, a 5s statement
timeout, and at most 10 connections. On RDS it also grants `rds_iam`, so the role logs in with IAM
tokens instead of a password. dbt handles access: an `on-run-start` hook grants usage on `marts`,
and a `grants` config re-grants `select` each time dbt rebuilds a mart table, since a new table
starts with no grants. `tests/assert_api_reader_grants.sql` fails the build if api_reader can't read a
mart or can read anything in `raw`, `staging` or `seeds`.

The role can switch `default_transaction_read_only` off itself, so writes are really blocked by
it having no write privileges. The setting is a second layer.

## Tableau

Tableau Public can't connect to Postgres, so the dashboard reads a CSV extract of
`marts.rpt_postings`: one row per posting with display labels, `company_name`, annualised USD
pay (`salary_annual_mid_usd`) and `data_as_of` already on it. Aggregation happens in Tableau.

    cd dbt && uv run dbt build && cd ..
    uv run datatrace-export          # writes exports/rpt_postings.csv

To refresh the published dashboard, re-export, open the workbook in Tableau Public, refresh
the data source and save it back to Tableau Public. Filter on `is_open` for current postings;
RemoteOK rows count as open because its feed can't tell us when a job closes.
