# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

# Job Market Analytics Pipeline

I'm a UC Davis Data Science student (rising 2nd year) building this as a
portfolio project for Data Analyst / Data Engineer roles. Learning by
building — give real code and commands, not conceptual explanations unless
I ask.

## Stack
Python ingestion → AWS Lambda on an EventBridge schedule → S3 (raw landing)
→ RDS Postgres → dbt (staging → marts) → a read-only API behind API Gateway
→ Next.js on Vercel. Step Functions chains ingest, load and dbt into one
daily run at 06:00 America/Los_Angeles. A Tableau Public workbook reads a
CSV extract alongside the site, not as the endpoint.

Everything AWS is in us-east-2 — an account SCP denies every other region —
and the account is reached with `aws login --profile datatrace`, not IAM
user keys. The live API is an HTTP API; the site is the `datatrace` project
on the `data-trace` Vercel team, built from `web/`.

## Layout
- `src/datatrace/` — ingestion, loader, dbt and API Lambda handlers
- `dbt/` — staging and marts models; `profiles.yml` sits next to the project
- `infra/` — one shell script per AWS component, all safe to re-run
- `web/` — Next.js App Router frontend; Vercel's root directory is this folder
- `tests/` — pytest; loader tests skip when local Postgres isn't running

## Commands

    uv sync
    uv run pytest                                # 46 tests
    uv run pytest tests/test_api.py -k postings  # a single area
    uv run ruff check src tests
    uv run ruff format src tests

    docker compose up -d                         # local Postgres for dbt dev
    uv run datatrace-load --src data/raw
    cd dbt && uv run dbt build                   # dev; --target prod hits RDS
    uv run datatrace-export                      # CSV extract for Tableau

    cd web && npm install && npm run dev
    cd web && npm run build                      # needs DATATRACE_API_URL reachable

Deploys, each safe to re-run:

    infra/api.sh                                      # API Lambda + Gateway routes
    infra/dbt.sh                                      # rebuild the marts in RDS
    infra/pipeline.sh                                 # the Step Functions state machine
    infra/db_admin.sh '{"scripts":["check_data.sql"]}' # read-only SQL against RDS

`web/` deploys from GitHub on push to `main`. The landing page is
prerendered at build time, so a build fails outright if the API is
unreachable — that is deliberate, but it means an RDS outage blocks deploys.

## Sources
Greenhouse, Lever, Ashby, SmartRecruiters and Rippling public JSON APIs, plus
RemoteOK. Workday, iCIMS, Oracle and similar enterprise ATSs are out of scope
(no clean public API). US jobs only —
raw lands unfiltered, US filter happens in dbt staging. Arbeitnow dropped
(EU-only board). No scraping LinkedIn/Indeed.

## Dates
`first_seen_at` is when ingestion first saw a row, not when the role went up.
Anything user-facing that means "posted" reads `published_at`, the board's own
date, falling back to `first_seen_at` only where a source gives none.

## Working rules
- Write code like a competent human under normal time pressure — clean, 
  minimal comments only where logic needs explaining. No comment-per-line, 
  no decorative section dividers, no emoji in code or commits.
- Flag AWS free-tier limits and real dollar cost risk before running 
  anything that could incur charges.
- Be direct about what's wrong or fragile in my code/SQL — don't soften it.
- Flag whether a design choice is resume-defensible (I could explain it in 
  an interview) or cargo-culted.
- The pipeline is built end to end, so changes land one stage at a time.
  Don't jump ahead unless I ask.
