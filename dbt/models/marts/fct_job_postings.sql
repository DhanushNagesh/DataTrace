-- One row per US-accessible posting: latest attributes plus when the pipeline first and last saw it
with observations as (
    select * from {{ ref('stg_job_postings') }}
),

latest as (
    select distinct on (posting_key) *
    from observations
    order by posting_key, observed_at desc
),

seen as (
    select
        posting_key,
        min(observed_at) as first_seen_at,
        max(observed_at) as last_seen_at,
        count(*) as times_seen
    from observations
    group by posting_key
),

board_latest as (
    select source, board, max(observed_at) as latest_run_at
    from {{ ref('stg_board_runs') }}
    group by source, board
)

select
    latest.posting_key,
    {{ company_key('latest.company') }} as company_key,
    latest.source,
    latest.board,
    latest.posting_id,
    latest.title,
    latest.location,
    latest.department,
    latest.employment_type,
    latest.is_remote,
    latest.is_us,
    latest.is_remote_anywhere,
    latest.salary_min,
    latest.salary_max,
    latest.salary_currency,
    latest.salary_interval,
    latest.url,
    latest.published_at,
    seen.first_seen_at,
    seen.last_seen_at,
    seen.times_seen,
    -- Active means present in the board's latest run, so a board outage doesn't close its postings.
    -- RemoteOK's feed only holds its newest ~100 jobs, so dropping out of it says nothing about closing.
    case
        when latest.source = 'remoteok' then null
        else seen.last_seen_at = board_latest.latest_run_at
    end as is_active,
    -- published_at predates the pipeline, so this isn't capped at how long ingestion has been running
    extract(epoch from seen.last_seen_at - coalesce(latest.published_at, seen.first_seen_at)) / 86400
        as days_listed
from latest
join seen using (posting_key)
join board_latest
    on board_latest.source = latest.source
    and board_latest.board is not distinct from latest.board
