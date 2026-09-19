-- How long postings stay up before closing, by role family. Only closed postings count, so early
-- on this is biased toward roles that fill (or get pulled) fast; the slow ones haven't closed yet.
select
    role_family,
    count(*) as closed_postings,
    round(percentile_cont(0.5) within group (order by days_listed)::numeric, 1) as median_days,
    round(percentile_cont(0.9) within group (order by days_listed)::numeric, 1) as p90_days
from {{ ref('fct_job_postings') }}
where is_active = false
group by role_family
order by median_days
