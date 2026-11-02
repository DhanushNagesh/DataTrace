-- One row per US-accessible posting: latest attributes plus when the pipeline first and last saw it
with postings as (
    -- int_postings_seen is incremental, so it keeps rows from boards retired after they landed
    select * from {{ ref('int_postings_seen') }}
    where {{ not_retired_board() }}
),

board_latest as (
    select source, board, max(observed_at) as latest_run_at
    from {{ ref('stg_board_runs') }}
    group by source, board
),

assembled as (
select
    p.posting_key,
    {{ company_key('p.company') }} as company_key,
    p.source,
    p.board,
    p.posting_id,
    p.title,
    {{ role_family('p.title', 'p.department') }} as role_family,
    {{ seniority('p.title') }} as seniority,
    p.location,
    p.department,
    p.employment_type,
    p.is_remote,
    p.is_us,
    p.is_remote_anywhere,
    p.salary_min,
    p.salary_max,
    p.salary_currency,
    p.salary_interval,
    p.url,
    p.published_at,
    p.first_seen_at,
    p.last_seen_at,
    p.times_seen,
    -- Active means present in the board's latest run, so a board outage doesn't close its postings.
    -- RemoteOK's feed only holds its newest ~100 jobs, so dropping out of it says nothing about closing.
    case
        when p.source = 'remoteok' then null
        else p.last_seen_at = board_latest.latest_run_at
    end as is_active,
    -- published_at predates the pipeline, so this isn't capped at how long ingestion has been running
    extract(epoch from p.last_seen_at - coalesce(p.published_at, p.first_seen_at)) / 86400
        as days_listed
from postings p
join board_latest
    on board_latest.source = p.source
    and board_latest.board is not distinct from p.board
)

select
    *,
    -- A board that never expires a req keeps returning it in every run, so is_active stays true
    -- forever: the oldest posting still counted open was published in 2019. Past the cutoff the
    -- posting is treated as closed no matter what the board says. This trades away genuine
    -- evergreen reqs, which do exist, for not reporting seven-year-old roles as open.
    days_listed > {{ var('stale_after_days') }} as is_stale
from assembled
