-- Per day and role family: postings open (stock), newly opened and closed (flows), and the
-- week-over-week change in stock. Needs a few weeks of daily runs before the trend means anything.
with postings as (
    select
        f.role_family,
        f.first_seen_at::date as opened_on,
        -- First day the posting was gone, assuming daily runs
        case when f.is_active = false then f.last_seen_at::date + 1 end as closed_on,
        -- Everything in a board's first run already existed; counting it as opened that day
        -- would make day one look like a hiring boom.
        f.first_seen_at > b.first_run_at as is_new
    from {{ ref('fct_job_postings') }} f
    join (
        select source, board, min(observed_at) as first_run_at
        from {{ ref('stg_board_runs') }}
        group by source, board
    ) b on b.source = f.source and b.board is not distinct from f.board
    where f.source <> 'remoteok'
),

days as (
    select generate_series(
        (select min(opened_on) from postings),
        (select max(observed_at)::date from {{ ref('stg_board_runs') }}),
        interval '1 day'
    )::date as day
),

daily as (
    select
        d.day,
        p.role_family,
        count(*) filter (where p.opened_on <= d.day and (p.closed_on is null or p.closed_on > d.day)) as open_postings,
        count(*) filter (where p.opened_on = d.day and p.is_new) as opened,
        count(*) filter (where p.closed_on = d.day) as closed
    from days d
    cross join postings p
    group by d.day, p.role_family
)

select
    *,
    open_postings - lag(open_postings, 7) over (partition by role_family order by day) as wow_change
from daily
order by role_family, day
