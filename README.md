# DataTrace

**[Live site](https://datatrace-gamma.vercel.app/)** · **[Tableau dashboard](https://public.tableau.com/app/profile/dhanush.nagesh/viz/DataTraceUSTechJobPostings/Dashboard1)**

DataTrace collects software and data job postings from public job board APIs every
morning, keeps every raw response in S3, models them in Postgres with dbt, and serves
the results through a read-only API to a Next.js dashboard. It answers the questions a
job seeker actually has — which role families are hiring, what they pay, how fast
postings close — from ~11k open US postings across 76 company boards.

Everything runs on a schedule with no machine of mine involved: one EventBridge trigger
starts a Step Functions execution at 06:00 Pacific, and about four and a half minutes
later the dashboard is showing the new day's numbers.

## The dashboard

Live at **[datatrace-gamma.vercel.app](https://datatrace-gamma.vercel.app/)**.

![DataTrace /intelligence — headline stat tiles and the role mix chart](docs/images/home.png)

*`/intelligence`: headline counts, then role mix — the first of five server-rendered sections.*

![The postings page — filtered posting list with facet popovers](docs/images/postings.png)

*`/postings`, the front door: every filter lives in the URL, so a filtered view is shareable.*

## Architecture

```
DAILY RUN  —  06:00 America/Los_Angeles, one Step Functions execution, ~4.5 min

   76 company boards        ┌──────────┐      ┌──────────┐      ┌──────────────┐
   6 public APIs      ───►  │  ingest  │ ───► │   load   │ ───► │     dbt      │
                            │  Lambda  │      │  Lambda  │      │  Lambda      │
                            │  (zip)   │      │  (zip)   │      │  (container) │
                            └──────────┘      └──────────┘      └──────────────┘
                                  │                 │                   │
                                  ▼                 ▼                   ▼
                             S3 raw JSON  ───► raw.job_postings ─► staging ─► marts
                          (source of truth)    RDS Postgres 17, private VPC

READ PATH

   marts ───► API Lambda ───► HTTP API Gateway ───► Next.js on Vercel
     │        (api_reader,     (throttled,           (server components,
     │         read-only)       5 min cache)          5 min revalidate)
     │
     └──────► CSV extract ───► Tableau Public
```

The three pipeline stages run inside a VPC with **no internet gateway**, so nothing in it
can reach or be reached from the internet. S3 is read through a free gateway endpoint, and
the API Lambda is the only thing exposed, behind API Gateway.

Raw JSON in S3 is the source of truth. The warehouse is disposable — if RDS is lost, a
reload and a `dbt build` rebuild it from the bucket, which is why backups are kept to a
single day.

## Stack

| Layer | What it uses |
|---|---|
| Ingestion | Python 3.13, `requests`, a source module per board API |
| Raw landing | S3, newline-delimited JSON plus a run manifest |
| Warehouse | RDS Postgres 17 (`db.t4g.micro`, private, IAM auth) |
| Transformation | dbt (dbt-postgres), staging views → mart tables, seeds and tests |
| Orchestration | Step Functions Standard, triggered by EventBridge Scheduler |
| Compute | Lambda — three zips (arm64, python3.13) and one container image from ECR |
| API | Lambda + API Gateway **HTTP API**, `psycopg` |
| Frontend | Next.js App Router (React Server Components), Recharts, on Vercel |
| BI | Tableau Public, reading a CSV extract |
| Secrets & auth | IAM database auth, Parameter Store, per-function IAM roles |
| Monitoring | CloudWatch alarms → SNS email, AWS Budgets |
| Tooling | uv, pytest (46 tests), ruff, Docker Compose for local Postgres |

## Sources and scope

Public JSON APIs from **Greenhouse** (54 boards), **Ashby** (12), **Lever** (5),
**SmartRecruiters** (4) and **Rippling** (1), plus the **RemoteOK** feed. Boards are
listed in `config/boards.toml` and were picked for US-heavy postings across tech,
fintech, healthcare, consumer, gaming and hardware.

Scope is US-accessible postings. Raw data lands unfiltered and the US filter happens in
dbt staging, so changing the definition is a rebuild, not a re-ingest. Workday, iCIMS and
Oracle are out of scope — no clean public API — and nothing scrapes LinkedIn or Indeed.

Two source quirks the ingestion handles. SmartRecruiters and Rippling omit the
description from their list endpoints, so each posting needs its own detail request;
`http.get_many` runs those 8 at a time and skips a posting that 404s between the list and
detail calls. Rippling repeats a job once per location, so the source merges those before
fetching details.

## Layout

```
src/datatrace/     ingestion, loader, dbt and API Lambda handlers
  sources/         one module per board API
config/            boards.toml — the company board list
dbt/               staging and mart models, macros, seeds, tests
infra/             one shell script per AWS component, all safe to re-run
web/               Next.js frontend (Vercel's root directory)
tests/             pytest
```

## Running it locally

```
uv sync
docker compose up -d                  # Postgres 17 for dbt development
echo 'DATABASE_URL=postgresql://datatrace:datatrace@localhost:5432/datatrace' > .env
uv run datatrace-load --src data/raw
cd dbt && uv run dbt build
```

dbt development runs against Docker Postgres, not RDS, so iterating on models costs
nothing and RDS only comes up once the models work. Create the read-only API role once per
database, before the first build:

```
docker compose exec -T postgres psql -U datatrace -d datatrace -v ON_ERROR_STOP=1 < infra/db_roles.sql
```

Tests use a separate `datatrace_test` database and skip the loader tests when Postgres
isn't running:

```
uv run pytest
uv run ruff check src tests
```

One local gotcha: keep the repo out of iCloud-synced folders (`~/Documents`, `~/Desktop`).
iCloud sets the macOS `hidden` flag on dot-named files it syncs, Python 3.13+ skips hidden
`.pth` files, and the venv's editable install silently stops importing `datatrace`. It also
syncs `.git`, which risks corrupting the repo.

## The warehouse

`profiles.yml` sits next to the dbt project, with a `dev` target on Docker Postgres and a
`prod` target on RDS reading `DBT_HOST`, `DBT_USER` and `DBT_PASSWORD` from the environment.

**Staging** (views). `stg_<source>__postings` gives one typed row per posting per ingest
run, all countries, with an `is_us` flag. `stg_job_postings` unions them and filters to
US-accessible postings: a US location, or remote with no region stated.

**Marts** (tables).

| Model | Grain |
|---|---|
| `fct_job_postings` | one row per US posting, latest attributes, `days_listed`, `is_active` |
| `dim_companies` | one row per company, keyed on md5 of the normalized name |
| `rpt_postings` | the display-ready posting list, labels and USD pay resolved |
| `rpt_stats` | one row: headline counts and the freshness stamp |
| `rpt_role_mix`, `rpt_seniority_mix` | share of open postings by family, and within it |
| `rpt_salary_by_role` | p25 / median / p75 annualised USD pay |
| `rpt_time_to_close`, `rpt_daily_flow` | median and p90 days listed; daily open/opened/closed |

The `rpt_*` marts are small — one row for `rpt_stats`, tens to a few hundred for the rest
— and each is already the shape a dashboard section needs. That's the point: the API serves
every one of them with a plain `select *` instead of aggregating 11k postings per request,
and the aggregation happens once a day in dbt.

`is_active` means a posting was seen in the latest run that returned *its* board, so one
board's outage doesn't mark its postings closed. It's null for RemoteOK, whose feed is a
rolling window of recent jobs rather than a list of open ones.

### Modeling decisions worth knowing

**Dates.** `first_seen_at` is when ingestion first saw a row, not when the role went up.
Anything user-facing that means "posted" reads `published_at`, the board's own date,
falling back to `first_seen_at` only where a source gives none. This matters more than it
sounds: counted on `first_seen_at`, a young warehouse makes every posting look new and the
"new this week" headline read 11,285 of 11,285. Lever publish dates that are actually ATS
migration stamps are dropped in staging — they made real postings look like 4,600-day
listings — and `assert_no_migration_stamp_dates.sql` fails the build if the pattern shows
up in another source.

**US classification.** Lever, Ashby, SmartRecruiters and Rippling carry country fields.
Greenhouse and RemoteOK only have free text, so they go through the `is_us_location` macro
(regex over country names, state names and codes, and major cities). `seeds/us_location_cases.csv`
holds hand-labelled locations and a test fails the build if the macro gets any of them
wrong. A Greenhouse posting whose location is just "Remote" or "N/A" falls back to its
`offices` list; a bare "Remote", "Worldwide" or blank RemoteOK location counts as
remote-anywhere, which is treated as US-accessible.

**Shared labels.** Display labels (`Data Engineering`, `Staff+`) and the seniority sort
order come from the `role_family_label`, `seniority_label` and `seniority_rank` macros, and
every mart calls them. Without that, four of the five dashboard sections would serve raw
`data_engineering` while the fifth served `Data Engineering`, and nothing could cross-filter.

**Company names.** Lever and Ashby put no company name in their APIs, so
`seeds/board_companies.csv` maps source and board to a display name and a warn-level test
flags boards missing from it. Salary periods are normalised by the `pay_interval` macro;
Rippling lists several tiered ranges per posting and staging keeps the first USD one.

## AWS

The account is on the AWS (new) free plan, so work happens in a project account
(264350941264) reached through a login session rather than IAM user keys. An AWS-managed
SCP limits the account to **us-east-2** — Lambda, Scheduler, RDS and S3 bucket creation are
denied everywhere else.

```
aws login --profile datatrace
export AWS_PROFILE=datatrace AWS_REGION=us-east-2
```

Every script in `infra/` is safe to re-run.

| Script | What it builds |
|---|---|
| `s3_raw_bucket.sh` | the raw landing bucket |
| `network.sh` | VPC, two private subnets, security groups, S3 gateway endpoint |
| `rds.sh` | the Postgres instance |
| `build_lambda.sh` | the ingest zip |
| `loader.sh` | build, deploy and invoke the loader |
| `dbt.sh` | build the image, push to ECR, run `dbt build` against prod |
| `api.sh [origin]` | API Lambda plus the Gateway routes |
| `pipeline.sh` | the state machine, and repoints the schedule at it |
| `db_admin.sh` | run a bundled SQL script inside the VPC |
| `alarms.sh`, `budget.sh` | CloudWatch alarms and the monthly budget |

### Ingest

`datatrace.lambda_handler.handler` wraps the same `run()` as the CLI, reading
`DATATRACE_OUT` for the destination and accepting an optional `{"sources": [...]}` event
for test invokes. The zip is about 650K — `requests`, the package and `boards.toml` —
and runs on python3.13 arm64 with 512 MB and a 5 minute timeout. A full run takes about
3.5 minutes, most of it the ~2,000 SmartRecruiters detail requests.

```
uv run datatrace-ingest --out s3://datatrace-raw-264350941264-us-east-2/raw
infra/build_lambda.sh
aws lambda update-function-code --function-name datatrace-ingest --zip-file fileb://dist/ingest.zip
```

`botocore[crt]` is a dev dependency because boto3 needs it to read `aws login` credentials;
in Lambda the execution role handles that instead.

### Load

`datatrace-load` runs the same `load()` as the CLI, inside the VPC. It finds run manifests
that haven't been loaded yet and copies each run's records into `raw.job_postings` (one row
per posting, payload as `jsonb`) in a single transaction, then records the manifest in
`raw.loaded_runs`. Rerunning is a no-op and a run that fails partway leaves nothing behind.

It logs in as `datatrace_pipeline` with an IAM token that `db.connect()` signs locally, so
the function holds no database password, and its role may read `raw/` in the bucket and
`rds-db:connect` as that one user, nothing else.

Long invokes need `--cli-read-timeout 0`: the CLI's 60s default gives up and retries, which
starts a second loader run alongside the first. The `raw.job_postings` primary key rejects
the duplicate and that transaction rolls back, so a race costs time, not correctness.

### dbt

dbt-postgres is far past the 250 MB zip limit, so `datatrace-dbt` ships as a container
image (`infra/dbt.Dockerfile`, pushed to ECR with a lifecycle policy keeping the last two
images). The project is baked into the image, and an invoke may only pick a command from
`dbt_handler.ALLOWED` — `run-operation` is excluded, since it would run arbitrary SQL as
the owner of every table.

```
infra/dbt.sh                          # dbt build against prod
infra/dbt.sh '{"command":["test"]}'
```

Three things Lambda forces on dbt, all handled in `dbt_handler`:

- No `/dev/shm`, so POSIX semaphores fail. dbt's mp context and its `DbtThreadPool` are
  swapped for thread locks and a `ThreadPoolExecutor` — dbt runs nodes in threads anyway.
  Both patches have to happen before `dbt.cli.main` is imported.
- Only `/tmp` is writable, so `DBT_LOG_PATH` and `DBT_TARGET_PATH` point there.
- Lambda rejects the OCI image index buildx produces by default, hence
  `--provenance=false --sbom=false`.

Prod runs two threads, not four: on `db.t4g.micro`, four parallel connections exhausted the
instance's CPU credits and later connections timed out mid-build.

### Database and admin access

`network.sh` creates the `datatrace` VPC (10.20.0.0/16) with two private subnets in
us-east-2a/b. With no internet gateway there's also no need for a NAT Gateway (~$32/mo).
`datatrace-rds` accepts 5432 only from the `datatrace-api-lambda` and
`datatrace-pipeline-lambda` groups, and the rules name those groups rather than IP ranges.

The instance is `db.t4g.micro`, Postgres 17.11, 20 GB gp3 with no autoscaling, single-AZ,
encrypted, not publicly accessible, IAM auth on, 1-day backups, deletion protection on. The
random master password lives in Parameter Store (free; Secrets Manager is $0.40/mo per
secret) at `/datatrace/rds/master-password`.

Because RDS has no public address, admin SQL can't run from a laptop. `datatrace-db-admin`
sits in the VPC and applies SQL scripts that ship in its own zip — an invoke may only name
a bundled file, never supply SQL. Scripts run in one transaction and rows from the last
statement come back in the response.

```
infra/db_admin.sh                                     # applies db_roles.sql
infra/db_admin.sh '{"scripts":["check_roles.sql"]}'   # what api_reader can do
infra/db_admin.sh '{"scripts":["check_load.sql"]}'    # runs and rows landed so far
```

It connects as the master user, with the password injected as an environment variable at
deploy time. That's the one credential IAM can't replace: granting a role `rds_iam`
requires a password login first. Every role it creates uses IAM tokens instead.

### Schedule and alarms

`pipeline.sh` builds the `datatrace-pipeline` state machine — ingest, then load, then dbt,
each waiting on the one before. The `datatrace-ingest-daily` schedule starts the state
machine rather than invoking ingest directly, so there's still exactly one trigger at 06:00
Pacific. Any failing step publishes the execution state to SNS and ends the run as failed.
Step Functions Standard is effectively free here (~120 of 4,000 free monthly transitions).

```
infra/pipeline.sh          # create or update, and repoint the schedule
infra/pipeline.sh run      # start an execution now
```

Load and dbt retry twice. Ingest retries only on Lambda service errors, since a failed board
is already handled per-source and a rerun would refetch every board. The state machine has a
one-hour timeout, so a hung run ends and counts as timed out instead of blocking tomorrow's.

`infra/alarms.sh [email]` wires four alarms to the `datatrace-alerts` SNS topic:

- `datatrace-ingest-errors` — the ingest Lambda crashed or timed out
- `datatrace-ingest-source-failures` — a board failed, counted from logs by a metric filter;
  the run manifest says which
- `datatrace-pipeline-failed` — an execution failed, timed out or was aborted, as one alarm
  over the sum of all three metrics
- `datatrace-pipeline-missed` — no execution started in 24h, treating missing data as
  breaching. A failing pipeline is loud; a pipeline that never starts is silent, and this is
  what catches it.

Four alarms, and CloudWatch only bills after ten.

## API

`infra/api.sh [origin]` deploys `datatrace-api` into the VPC behind an API Gateway **HTTP
API** — not a REST API: $1 per million requests instead of $3.50, with CORS and throttling
built in.

| Route | Source | Returns |
|---|---|---|
| `GET /stats` | `rpt_stats` | headline counts and the data freshness timestamp |
| `GET /postings` | `rpt_postings` | open postings, filtered and paged |
| `GET /role-mix` | `rpt_role_mix` | share of open postings by role family |
| `GET /seniority-mix` | `rpt_seniority_mix` | seniority split within each family |
| `GET /salary-by-role` | `rpt_salary_by_role` | p25/median/p75 annualised USD pay |
| `GET /time-to-close` | `rpt_time_to_close` | median/p90 days listed, closed postings only |
| `GET /daily-flow` | `rpt_daily_flow` | daily open/opened/closed, with `wow_change` |

Every route but `/postings` is a straight `select *` from its mart. `/postings` still
filters and pages, since it serves rows rather than a fixed aggregate, and takes `q`,
`company`, `role_family`, `seniority`, `work_mode`, `source`, `min_salary`, `sort`, `limit`
and `offset`. Every filter is a bound parameter that a null switches off. `sort` is the one
value that becomes SQL text, so it's looked up in a whitelist — a request can pick an
ordering, never write one — and each ordering ends on `posting_key` so paging can't repeat
or skip a row. The response carries a `total` for the filtered set computed with
`count(*) over ()` in the same scan the page comes from: one query, not two.

The Lambda connects as `api_reader`, which can read `marts` and nothing else, using an IAM
token. dbt maintains that access — an `on-run-start` hook grants usage on `marts` and a
`grants` config re-grants `select` on every rebuild, since a new table starts with no
grants — and `assert_api_reader_grants.sql` fails the build if `api_reader` can't read a
mart or *can* read anything in `raw`, `staging` or `seeds`. The role also runs with
read-only transactions, a 5s statement timeout and at most 10 connections. It can turn the
read-only default off itself, so writes are really blocked by it having no write privileges;
the setting is a second layer.

Routing lives in the Gateway, so anything not listed above is a 404 that never reaches the
Lambda. The stage throttles at 10 req/s with a burst of 20, and responses carry
`cache-control: max-age=300`. CORS is a browser rule, not access control — `curl` ignores
it — so the real protections are the throttle, the read-only role, bound parameters and the
caps on `limit`, `offset` and `q`.

## Frontend

`web/` is a Next.js App Router site on Vercel. Every page is a React Server Component, so
the browser never talks to the API — Vercel's Node runtime does. The Gateway URL stays in
`DATATRACE_API_URL`, a server-side variable rather than `NEXT_PUBLIC_`, and the API needs no
CORS configuration at all.

```
cd web
npm install
echo 'DATATRACE_API_URL=<the URL infra/api.sh printed>' > .env.local
npm run dev
```

`/` redirects to `/postings`: the roles list is the front door, and the charts sit one click
away at `/intelligence`.

`/intelligence` is statically prerendered. Every API fetch sets `revalidate: 300`
(`web/lib/api.ts`), matching the `cache-control` the Lambda sends. One visitor's request
warms it and everyone else that five minutes is served from the edge cache, so a burst of
traffic is a handful of Lambda invocations rather than one per visitor. The data changes
once a day, so nothing is ever meaningfully stale.

`/postings` is dynamic because its filters live in the URL. The free-text fields are a plain
GET `<form>` and each facet is a popover of server-built `<Link>`s, so every filtered view is
a shareable, cacheable URL and nothing fetches from the browser. Radix's popover is the only
client-side state on the page.

The mix and salary charts are server-rendered HTML/CSS marks with every value printed, so
they ship no JavaScript. Only the two that earn a hover layer — time-to-close and daily flow
— are client components using Recharts.

Company logos come from `/logo/[domain]`, a route handler that proxies an icon service. No
source API gives a company website, so the domain is guessed from the display name and a
miss is the expected case: the route answers with a drawn monogram rather than a 404, which
is why the card stays a server component with no broken-image state. Proxying rather than
hotlinking means the visitor's browser only ever talks to this site, so browsing the board
doesn't hand a third party the list of companies you looked at. Icons cache for a week.

The look is three values — cream paper, near-black ink, one burnt orange — with Playfair
Display for headlines, Source Serif for prose and JetBrains Mono for every label and number,
1px rules and no border radius. Light only; tokens live in `app/globals.css`. Orange is the
single hue: solid orange is the primary measure in every chart and the one action in every
control, and a comparison series is carried by a 45° hatch or a dashed stroke rather than a
second colour — the channel a colour-blind or black-and-white reader falls back to anyway.
At 4.84:1 on the cream it clears AA as text, and white on it clears 5.18:1, so it works as
both fill and foreground. Recharts passes `var(--accent)` straight through to SVG, so the
charts need no palette config.

On Vercel, set the project's Root Directory to `web` and add `DATATRACE_API_URL` for all
three environments.

## Tableau

Published at **[public.tableau.com/…/DataTraceUSTechJobPostings](https://public.tableau.com/app/profile/dhanush.nagesh/viz/DataTraceUSTechJobPostings/Dashboard1)**.

Tableau Public can't connect to Postgres, so the workbook reads a CSV extract of
`marts.rpt_postings` — one row per posting with display labels, `company_name`, annualised
USD pay and `data_as_of` already on it. Aggregation happens in Tableau.

```
cd dbt && uv run dbt build && cd ..
uv run datatrace-export          # writes exports/rpt_postings.csv
```

To refresh the published dashboard, re-export, open the workbook in Tableau Public, refresh
the data source and save it back. Filter on `is_open` for current postings; RemoteOK rows
count as open because its feed can't say when a job closes.

![Tableau Public workbook reading the rpt_postings CSV extract](docs/images/tableau.png)

*The Tableau Public workbook, reading the same `rpt_postings` extract.*

## Cost

RDS is the only meaningful line item at roughly **$14/month** until the instance is deleted,
plus about $0.25/month of ECR storage. Everything else — Lambda, Step Functions, EventBridge,
S3, Parameter Store, four CloudWatch alarms, API Gateway at this traffic, and Vercel Hobby —
sits inside free tiers. `infra/budget.sh [email] [limit]` sets a monthly budget (default $25)
with email alerts; AWS Budgets is free for the first two.

The choices that keep it there are deliberate: no NAT Gateway (~$32/mo avoided), an HTTP API
instead of REST, Parameter Store instead of Secrets Manager, a 5-minute edge cache in front
of the API, and pre-aggregated marts so a page view is a single-row read.

## License

MIT — see [LICENSE](LICENSE).
