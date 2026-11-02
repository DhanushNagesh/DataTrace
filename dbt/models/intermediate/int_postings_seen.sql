{{ config(materialized='incremental', unique_key='posting_key') }}

-- One row per posting: its latest attributes and when the pipeline first and last saw it.
-- Each run only parses observations loaded since the last one, so the work tracks one day's
-- volume instead of all of raw. An observation loaded late (older than what is already here)
-- still counts toward first_seen/times_seen but can't overwrite newer attributes, because the
-- existing row competes with the new observations for "latest".
--
-- Changing a staging macro (is_us_location, say) only affects rows loaded afterwards.
-- Reclassify history with: dbt build --full-refresh --select int_postings_seen+
-- In prod that no longer fits in one Lambda invoke; infra/backfill.sh splits it into chunks
-- using the backfill_until var, which caps loaded_at for one run.

{% set cols = [
    'source', 'board', 'posting_id', 'company', 'title', 'location', 'department',
    'employment_type', 'is_remote', 'is_us', 'is_remote_anywhere', 'salary_min', 'salary_max',
    'salary_currency', 'salary_interval', 'url', 'published_at', 'source_updated_at',
] %}

with new_obs as (
    select * from {{ ref('stg_job_postings') }}
    where true
    {% if is_incremental() %}
        and loaded_at > (select coalesce(max(loaded_at), '-infinity') from {{ this }})
    {% endif %}
    {% if var('backfill_until', none) %}
        and loaded_at <= '{{ var("backfill_until") }}'::timestamptz
    {% endif %}
),

candidates as (
    select
        posting_key,
        {% for c in cols %}{{ c }},{% endfor %}
        observed_at,
        observed_at as first_seen_at,
        1 as times_seen,
        loaded_at
    from new_obs
    {% if is_incremental() %}
    union all
    select
        posting_key,
        {% for c in cols %}{{ c }},{% endfor %}
        last_seen_at,
        first_seen_at,
        times_seen,
        loaded_at
    from {{ this }}
    where posting_key in (select posting_key from new_obs)
    {% endif %}
),

latest as (
    select distinct on (posting_key) *
    from candidates
    order by posting_key, observed_at desc
),

seen as (
    select
        posting_key,
        min(first_seen_at) as first_seen_at,
        max(observed_at) as last_seen_at,
        sum(times_seen)::int as times_seen,
        max(loaded_at) as loaded_at
    from candidates
    group by posting_key
)

select
    latest.posting_key,
    {% for c in cols %}latest.{{ c }},
    {% endfor -%}
    seen.first_seen_at,
    seen.last_seen_at,
    seen.times_seen,
    seen.loaded_at
from latest
join seen using (posting_key)
