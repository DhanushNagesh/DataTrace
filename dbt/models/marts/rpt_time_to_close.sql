-- How long postings stay up before closing, by role family. Only closed postings count, so early
-- on this is biased toward roles that fill (or get pulled) fast; the slow ones haven't closed yet.
select
    {{ role_family_label('role_family') }} as role_family,
    count(*) as closed_postings,
    round(percentile_cont(0.5) within group (order by days_listed)::numeric, 1) as median_days,
    round(percentile_cont(0.9) within group (order by days_listed)::numeric, 1) as p90_days
from {{ ref('fct_job_postings') }}
-- Stale postings are excluded rather than counted as closing at the cutoff: we never saw them
-- close, and a seven-year days_listed would drag the median and p90 for its whole family.
where is_active = false and not is_stale
group by 1
order by median_days
