# DataTrace

**[Live site](https://datatrace-gamma.vercel.app/)** · **[Tableau dashboard](https://public.tableau.com/app/profile/dhanush.nagesh/viz/DataTraceUSTechJobPostings/Dashboard1)**

DataTrace is a data pipeline I built to track US software and data job postings. Every
morning it pulls postings from public job board APIs, saves the raw responses to S3,
loads them into Postgres, cleans and models them with dbt, and shows the results on a
Next.js dashboard through a small read-only API.

I started it because I was looking at internships and wanted real answers to questions
like which kinds of roles are hiring, what they pay, and how long postings stay up. Right
now it covers about 11k open US postings from 76 company boards.

The whole thing runs by itself. An EventBridge schedule kicks off a Step Functions run at
6:00 AM Pacific, and about 4.5 minutes later the dashboard has the new day's data.

## The dashboard

Live at **[datatrace-gamma.vercel.app](https://datatrace-gamma.vercel.app/)**.

![DataTrace /intelligence page with the stat tiles and the role mix chart](docs/images/home.png)

*`/intelligence`: headline counts and the role mix chart, the first of five sections.*

![The postings page with filters](docs/images/postings.png)

*`/postings` is the main page. All the filters are saved in the URL so you can share a filtered view.*

## How it works

```
DAILY RUN (6:00 AM Pacific, one Step Functions execution, about 4.5 min)

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

1. **Ingest** calls each job board's API and writes the raw JSON to S3.
2. **Load** copies any new runs from S3 into a `raw` table in Postgres.
3. **dbt** builds staging views and then the mart tables the dashboard uses.
4. **API** is a Lambda behind API Gateway that reads the marts and returns JSON.
5. **Frontend** is a Next.js site on Vercel that calls the API.

The pipeline Lambdas and the database are in a VPC with no internet gateway, so they can't
reach the internet and the internet can't reach them. S3 is accessed through a (free)
gateway endpoint. The only public piece is the API, which sits behind API Gateway.

I treat the raw JSON in S3 as the source of truth. If I lost the database I could just
reload from S3 and run `dbt build` again, so I only keep 1 day of RDS backups.

## Tech stack

| Part | What I used |
|---|---|
| Ingestion | Python 3.13, `requests`, one module per job board API |
| Raw storage | S3 (newline-delimited JSON plus a manifest for each run) |
| Database | RDS Postgres 17 (`db.t4g.micro`, private, IAM auth) |
| Transformations | dbt (dbt-postgres): staging views, mart tables, seeds and tests |
| Orchestration | Step Functions, started by EventBridge Scheduler |
| Compute | Lambda: three zips (arm64, python3.13) and one container image from ECR |
| API | Lambda + API Gateway **HTTP API**, `psycopg` |
| Frontend | Next.js App Router, Recharts, hosted on Vercel |
| BI | Tableau Public, reading a CSV export |
| Auth and secrets | IAM database auth, Parameter Store, one IAM role per function |
| Monitoring | CloudWatch alarms that email me through SNS, AWS Budgets |
| Tooling | uv, pytest (46 tests), ruff, Docker Compose for local Postgres |

## Data sources

I pull from the public JSON APIs of **Greenhouse** (54 boards), **Ashby** (12),
**Lever** (5), **SmartRecruiters** (3) and **Rippling** (1), plus the **RemoteOK** feed.
The list of boards is in `config/boards.toml`. I tried to pick companies with a lot of US
postings across tech, fintech, healthcare, consumer, gaming and hardware.

I only care about US jobs, but I save everything raw and do the US filter in dbt staging.
That way if I change what counts as "US" I just rebuild instead of re-downloading
everything. I left out Workday, iCIMS and Oracle because they don't have clean public
APIs, and I don't scrape LinkedIn or Indeed.

A few things about the sources that took me a while to figure out:

- **RemoteOK only returns its latest ~100 jobs.** There's no pagination, so every run gets
  99 rows and around 70 pass the US filter. A flat daily count from RemoteOK doesn't mean
  anything about the job market, it's just the API limit. I still keep it since it's the
  only source that isn't an ATS, but I leave it out of `rpt_daily_flow` and its `is_active`
  is null.
- **SmartRecruiters and Rippling don't include the job description in their list
  endpoints**, so I have to request each posting separately. `http.get_many` does these 8
  at a time and skips any posting that gets deleted (404) in between.
- **Rippling repeats the same job once for every location**, so I merge those before
  fetching details.

## Project layout

```
src/datatrace/     ingestion, loader, dbt and API Lambda handlers
  sources/         one module per job board API
config/            boards.toml (the list of company boards)
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

I develop the dbt models against Postgres in Docker instead of RDS, so trying things out is
free. Before the first build you need to create the read-only API role once:

```
docker compose exec -T postgres psql -U datatrace -d datatrace -v ON_ERROR_STOP=1 < infra/db_roles.sql
```

Tests use a separate `datatrace_test` database. The loader tests skip if Postgres isn't
running.

```
uv run pytest
uv run ruff check src tests
```

**Heads up:** don't put the repo in an iCloud synced folder like `~/Documents` or
`~/Desktop`. iCloud marks dotfiles as hidden, Python 3.13+ skips hidden `.pth` files, and
then the venv quietly stops being able to import `datatrace`. It also syncs `.git`, which
can corrupt the repo. I learned this the hard way and moved the project to `~/code`.

## The data model (dbt)

`profiles.yml` is next to the dbt project. The `dev` target uses Docker Postgres and the
`prod` target uses RDS, reading `DBT_HOST`, `DBT_USER` and `DBT_PASSWORD` from the
environment.

**Staging (views).** Each source has a `stg_<source>__postings` model with one typed row per
posting per ingest run, for all countries, with an `is_us` flag. `stg_job_postings` unions
them and keeps only US postings, meaning a US location or remote with no region listed.

**Marts (tables).**

| Model | One row per |
|---|---|
| `fct_job_postings` | US posting, with its latest attributes, `days_listed` and `is_active` |
| `dim_companies` | company, keyed on an md5 of the cleaned up name |
| `rpt_postings` | posting, ready to display with labels and USD pay filled in |
| `rpt_stats` | just one row: headline counts and when the data was updated |
| `rpt_role_mix`, `rpt_seniority_mix` | role family (and seniority within it), with share of open postings |
| `rpt_salary_by_role` | role family, with p25 / median / p75 yearly USD pay |
| `rpt_time_to_close`, `rpt_daily_flow` | median and p90 days listed; daily open/opened/closed counts |

The `rpt_*` tables are small (one row for `rpt_stats`, and tens to a few hundred rows for
the others), and each one is already shaped like the chart that uses it. So the API can
just do `select *` instead of aggregating 11k postings on every request. All the heavy work
happens once a day in dbt.

`is_active` means the posting showed up in the most recent run that successfully got *its*
board. I did it this way so that if one board's API is down for a day, all its postings
don't suddenly look closed. It's null for RemoteOK because that feed is just recent jobs,
not a list of open ones.

### Some decisions I had to make

**Dates.** `first_seen_at` is when my pipeline first saw a posting, not when the job was
actually posted. Anything on the site that means "posted" uses `published_at` (the date
from the job board), and only falls back to `first_seen_at` if the source doesn't give a
date. I got this wrong at first: when I counted on `first_seen_at`, every posting looked
new because the warehouse was new, and "new this week" said 11,285 out of 11,285. I also
found that some Lever publish dates were really dates from when a company migrated ATS
systems, which made real postings look like they'd been up for 4,600 days. Staging drops
those now, and `assert_no_migration_stamp_dates.sql` fails the build if the same thing shows
up in another source.

**Figuring out if a job is in the US.** Lever, Ashby, SmartRecruiters and Rippling have a
country field. Greenhouse and RemoteOK only have free text, so they go through the
`is_us_location` macro, which uses regex to match country names, state names and codes, and
big cities. I hand labeled a bunch of locations in `seeds/us_location_cases.csv`, and a test
fails if the macro gets any of them wrong. If a Greenhouse posting just says "Remote" or
"N/A", I check its `offices` list instead. A RemoteOK location that's "Remote", "Worldwide"
or blank counts as remote anywhere, which I treat as open to US applicants.

**Shared labels.** The display labels (like `Data Engineering` or `Staff+`) and the
seniority sort order come from the `role_family_label`, `seniority_label` and
`seniority_rank` macros, and every mart uses them. Before that, some sections showed
`data_engineering` and one showed `Data Engineering`, so they couldn't filter each other.

**Company names.** Lever and Ashby don't include a company name in their APIs, so
`seeds/board_companies.csv` maps each board to a name, and a warning test flags boards that
are missing. Salary periods (hourly, yearly, etc.) get normalized by the `pay_interval`
macro. Rippling sometimes lists several salary ranges per posting, and I just keep the first
USD one.

## AWS setup

I'm on the new AWS free plan, so everything is in a separate project account
that I log into with a login session instead of IAM user keys. An AWS managed SCP only allows
**us-east-2**, so things like Lambda, Scheduler, RDS and S3 bucket creation are blocked in
every other region.

```
aws login --profile datatrace
export AWS_PROFILE=datatrace AWS_REGION=us-east-2
```

Every script in `infra/` is safe to run more than once.

| Script | What it does |
|---|---|
| `s3_raw_bucket.sh` | creates the raw data bucket |
| `network.sh` | VPC, two private subnets, security groups, S3 gateway endpoint |
| `rds.sh` | the Postgres database |
| `build_lambda.sh` | builds the ingest zip |
| `loader.sh` | builds, deploys and runs the loader |
| `dbt.sh` | builds the image, pushes to ECR, runs `dbt build` on prod |
| `api.sh [origin]` | API Lambda and the Gateway routes |
| `pipeline.sh` | the Step Functions state machine, and points the schedule at it |
| `db_admin.sh` | runs a bundled SQL script inside the VPC |
| `alarms.sh`, `budget.sh` | CloudWatch alarms and the monthly budget |

### Ingest

`datatrace.lambda_handler.handler` wraps the same `run()` function the CLI uses. It reads
`DATATRACE_OUT` to know where to write, and you can pass `{"sources": [...]}` to test just a
few sources. The zip is about 650K (`requests`, the package and `boards.toml`) and runs on
python3.13 arm64 with 512 MB and a 5 minute timeout. A full run takes around 3.5 minutes,
mostly because of the ~2,000 SmartRecruiters detail requests.

```
uv run datatrace-ingest --out s3://datatrace-raw-<account-id>-us-east-2/raw
infra/build_lambda.sh
aws lambda update-function-code --function-name datatrace-ingest --zip-file fileb://dist/ingest.zip
```

`botocore[crt]` is a dev dependency because boto3 needs it to read `aws login` credentials
locally. In Lambda the execution role takes care of that.

### Load

`datatrace-load` runs the same `load()` as the CLI, but inside the VPC. It looks for run
manifests that haven't been loaded yet and copies each run into `raw.job_postings` (one row
per posting, with the payload as `jsonb`) in one transaction, then saves the manifest in
`raw.loaded_runs`. Running it again does nothing, and if a run fails halfway nothing gets
saved.

It logs in as `datatrace_pipeline` using an IAM token that `db.connect()` generates, so the
function doesn't need a database password. Its IAM role can only read `raw/` in the bucket
and connect to the database as that one user.

One thing I ran into: long invokes need `--cli-read-timeout 0`. The CLI's default is 60
seconds, and after that it retries, which starts a second loader run at the same time. The
primary key on `raw.job_postings` rejects the duplicates and that transaction rolls back, so
it wastes time but doesn't break the data.

### dbt

dbt-postgres is way bigger than Lambda's 250 MB zip limit, so `datatrace-dbt` runs as a
container image (`infra/dbt.Dockerfile`, pushed to ECR, and a lifecycle policy keeps the last
two images). The dbt project is built into the image. An invoke can only run commands listed
in `dbt_handler.ALLOWED`. I left out `run-operation` on purpose because it could run any SQL
as the owner of every table.

```
infra/dbt.sh                          # dbt build against prod
infra/dbt.sh '{"command":["test"]}'
```

Getting dbt to run in Lambda took some work. These are all handled in `dbt_handler`:

- Lambda has no `/dev/shm`, so POSIX semaphores don't work. I swap dbt's multiprocessing
  context and its `DbtThreadPool` for thread locks and a `ThreadPoolExecutor` (dbt runs
  nodes in threads anyway). Both patches have to happen before `dbt.cli.main` is imported.
- Only `/tmp` is writable, so `DBT_LOG_PATH` and `DBT_TARGET_PATH` point there.
- Lambda doesn't accept the OCI image index that buildx makes by default, so I build with
  `--provenance=false --sbom=false`.

Prod runs with 2 threads instead of 4. With 4, the `db.t4g.micro` instance ran out of CPU
credits and connections started timing out in the middle of the build.

### Database and admin access

`network.sh` creates the `datatrace` VPC (10.20.0.0/16) with two private subnets in
us-east-2a and us-east-2b. Since there's no internet gateway, I also don't need a NAT
Gateway, which would've been about $32/month. The `datatrace-rds` security group only allows
port 5432 from the `datatrace-api-lambda` and `datatrace-pipeline-lambda` security groups,
not from IP ranges.

The database is a `db.t4g.micro` running Postgres 17.11 with 20 GB gp3 storage, no
autoscaling, single AZ, encrypted, not public, IAM auth on, 1 day of backups and deletion
protection on. The master password is random and stored in Parameter Store at
`/datatrace/rds/master-password` (Parameter Store is free, Secrets Manager would be
$0.40/month per secret).

Since RDS has no public address, I can't run SQL from my laptop. Instead `datatrace-db-admin`
is a Lambda in the VPC that runs SQL scripts bundled in its zip. You can only pick one of
those files by name, you can't send it your own SQL. Scripts run in one transaction and the
rows from the last statement come back in the response.

```
infra/db_admin.sh                                     # applies db_roles.sql
infra/db_admin.sh '{"scripts":["check_roles.sql"]}'   # what api_reader can do
infra/db_admin.sh '{"scripts":["check_load.sql"]}'    # runs and rows loaded so far
```

This one connects as the master user, with the password passed in as an environment variable
when it's deployed. It's the one place I couldn't use IAM, because giving a role `rds_iam`
requires logging in with a password first. Every role it creates uses IAM tokens though.

### Schedule and alarms

`pipeline.sh` builds the `datatrace-pipeline` state machine: ingest, then load, then dbt,
each one waiting for the previous one. The `datatrace-ingest-daily` schedule starts the state
machine instead of calling ingest directly, so there's still only one trigger at 6:00 AM
Pacific. If any step fails, it sends the execution state to SNS and the run is marked failed.
Step Functions is basically free here (about 120 of the 4,000 free transitions a month).

```
infra/pipeline.sh          # create or update, and point the schedule at it
infra/pipeline.sh run      # start a run right now
```

Load and dbt retry twice. Ingest only retries on Lambda service errors, because a single
failing board is already handled per source and retrying the whole thing would refetch every
board. The state machine has a 1 hour timeout so a stuck run can't block the next day's.

`infra/alarms.sh [email]` sets up four alarms on the `datatrace-alerts` SNS topic:

- `datatrace-ingest-errors`: the ingest Lambda crashed or timed out
- `datatrace-ingest-source-failures`: a board failed (counted from the logs with a metric
  filter, and the run manifest says which one)
- `datatrace-pipeline-failed`: a run failed, timed out or was aborted (one alarm on the sum
  of all three metrics)
- `datatrace-pipeline-missed`: no run started in 24 hours, with missing data counted as a
  problem. A failing pipeline is easy to notice, but one that never starts is silent, so
  this is the alarm that catches that.

CloudWatch only charges after 10 alarms, so these four are free.

## API

`infra/api.sh [origin]` deploys `datatrace-api` into the VPC behind an API Gateway **HTTP
API**. I picked HTTP API over REST API because it's $1 per million requests instead of
$3.50 and has CORS and throttling built in.

| Route | Reads from | Returns |
|---|---|---|
| `GET /stats` | `rpt_stats` | headline counts and when the data was last updated |
| `GET /postings` | `rpt_postings` | open postings, filtered and paged |
| `GET /role-mix` | `rpt_role_mix` | share of open postings by role family |
| `GET /seniority-mix` | `rpt_seniority_mix` | seniority split within each family |
| `GET /salary-by-role` | `rpt_salary_by_role` | p25/median/p75 yearly USD pay |
| `GET /time-to-close` | `rpt_time_to_close` | median/p90 days listed, closed postings only |
| `GET /daily-flow` | `rpt_daily_flow` | daily open/opened/closed, with `wow_change` |

Every route except `/postings` is just a `select *` from its mart. `/postings` supports
filtering and paging with `q`, `company`, `role_family`, `seniority`, `work_mode`,
`source`, `min_salary`, `sort`, `limit` and `offset`. All the filters are bound parameters,
and passing null turns a filter off. `sort` is the only value that turns into SQL text, so
it's checked against a whitelist. You can choose an ordering but you can't write one. Every
ordering ends with `posting_key` so paging never repeats or skips a row. The response also
has a `total` for the filtered results, which I get with `count(*) over ()` in the same
query, so it's one query instead of two.

The Lambda connects as `api_reader` with an IAM token, and that role can only read `marts`.
dbt keeps the permissions up to date: an `on-run-start` hook grants usage on `marts`, and a
`grants` config grants `select` again on every rebuild (a rebuilt table starts with no
grants). `assert_api_reader_grants.sql` fails the build if `api_reader` can't read a mart, or
if it *can* read anything in `raw`, `staging` or `seeds`. The role also defaults to
read-only transactions, has a 5 second statement timeout and at most 10 connections. It
could turn off the read-only default itself, so the real protection is that it has no write
privileges. The read-only setting is just an extra layer.

Routing is done in API Gateway, so any path not in the table is a 404 that never reaches
the Lambda. The API is throttled to 10 requests/second with a burst of 20, and responses
have `cache-control: max-age=300`. CORS doesn't actually protect anything (`curl` ignores
it), so the real protections are the throttle, the read-only role, bound parameters, and
limits on `limit`, `offset` and `q`.

## Frontend

`web/` is a Next.js App Router site on Vercel. Every page is a React Server Component, so
the browser never calls the API directly, Vercel's server does. The API URL is in
`DATATRACE_API_URL`, which is server-side only (not `NEXT_PUBLIC_`), so the API doesn't need
any CORS setup.

```
cd web
npm install
echo 'DATATRACE_API_URL=<the URL infra/api.sh printed>' > .env.local
npm run dev
```

`/` redirects to `/postings` since the job list is the main page. The charts are at
`/intelligence`.

`/intelligence` is prerendered. Every API fetch uses `revalidate: 300` (`web/lib/api.ts`),
the same as the API's `cache-control`. The first visitor's request fills the cache and
everyone else for the next five minutes gets the cached version, so lots of traffic only
means a few Lambda calls. The data only changes once a day anyway.

`/postings` is dynamic because the filters are in the URL. The search boxes are a normal
GET `<form>`, and each filter dropdown is a popover of `<Link>`s built on the server. So
every filtered view is a URL you can share, and the browser doesn't fetch anything itself.
The Radix popover is the only client-side state on the page.

The role mix and salary charts are plain server-rendered HTML/CSS with every value printed,
so they don't need any JavaScript. Only the time-to-close and daily flow charts have hover
tooltips, and those are client components using Recharts.

Company logos come from `/logo/[domain]`, a route that proxies an icon service. None of the
job board APIs give a company website, so I guess the domain from the company name, and a
lot of the time it's wrong. When that happens the route returns a drawn monogram instead of
a 404, so there's never a broken image. Proxying (instead of linking the icon service
directly) means your browser only talks to my site, so a third party can't see which
companies you're looking at. Logos are cached for a week.

For the design I used three colors (cream background, near-black text, and one burnt
orange), Playfair Display for headings, Source Serif for body text and JetBrains Mono for
labels and numbers, with 1px lines and no rounded corners. It's light mode only, and the
colors are in `app/globals.css`. Orange is the only accent color. Where a chart compares two
series, the second one uses a hatch pattern or dashed line instead of a second color, which
also helps if you're colorblind or printing in black and white. The orange has a 4.84:1
contrast ratio on the cream background and white text on orange is 5.18:1, so both pass
WCAG AA. Recharts takes `var(--accent)` directly so the charts didn't need a separate
color config.

To deploy on Vercel, set the Root Directory to `web` and add `DATATRACE_API_URL` for all
three environments.

## Tableau

Published on **[Tableau Public](https://public.tableau.com/app/profile/dhanush.nagesh/viz/DataTraceUSTechJobPostings/Dashboard1)**.

Tableau Public can't connect to Postgres, so the workbook uses a CSV export of
`marts.rpt_postings`. That's one row per posting with the display labels, `company_name`,
yearly USD pay and `data_as_of` already included, and Tableau does the aggregation.

```
cd dbt && uv run dbt build && cd ..
uv run datatrace-export          # writes exports/rpt_postings.csv
```

To update the published dashboard, I re-export, open the workbook in Tableau Public, refresh
the data source and save it. Filter on `is_open` to see current postings. RemoteOK rows
always count as open since its feed can't tell when a job closes.

![Tableau Public workbook using the rpt_postings CSV export](docs/images/tableau.png)

*The Tableau Public workbook, using the same `rpt_postings` export.*

## Cost

RDS is the only real cost, at about **$14/month**, plus around $0.25/month for ECR storage.
Everything else (Lambda, Step Functions, EventBridge, S3, Parameter Store, the four
CloudWatch alarms, API Gateway at this amount of traffic, and Vercel Hobby) stays in the free
tier. `infra/budget.sh <email> [limit]` sets up a monthly budget (default $25) with email
alerts, and the first two AWS Budgets are free.

Things I did on purpose to keep costs low:

- No NAT Gateway (saves about $32/month)
- HTTP API instead of REST API
- Parameter Store instead of Secrets Manager
- A 5 minute cache in front of the API
- Pre-aggregated marts, so most page views are a tiny read

## What I learned

- Keeping raw data in S3 made the database feel low risk. I rebuilt the warehouse a bunch of
  times while fixing models and never had to re-download anything.
- Dates are harder than they look. The `first_seen_at` vs `published_at` bug made my
  headline number completely wrong and I didn't notice at first.
- dbt tests caught real problems, like the Lever migration dates and bad US location
  matches.
- Running dbt in Lambda needed a few workarounds, but it was still cheaper and simpler
  than running a server for one short job a day.
- Thinking about cost early (no NAT Gateway, HTTP API, Parameter Store) kept the whole
  project at around $14/month.

## License

MIT, see [LICENSE](LICENSE).
