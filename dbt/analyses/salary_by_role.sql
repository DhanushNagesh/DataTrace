-- Annualised USD salary midpoints by role family. Greenhouse and SmartRecruiters never publish pay,
-- so this describes companies on Ashby, Lever, Rippling and RemoteOK, not the whole sample.
with pay as (
    select
        role_family,
        source,
        (salary_min + coalesce(salary_max, salary_min)) / 2
            * case salary_interval
                when 'year' then 1
                when 'month' then 12
                when 'week' then 52
                when 'day' then 260
                when 'hour' then 2080
            end as annual_mid
    from {{ ref('fct_job_postings') }}
    where is_active is not false
        and salary_min > 0
        and salary_currency = 'USD'
)

select
    role_family,
    count(*) as n,
    string_agg(distinct source, ', ') as sources,
    round(percentile_cont(0.25) within group (order by annual_mid)) as p25,
    round(percentile_cont(0.5) within group (order by annual_mid)) as median,
    round(percentile_cont(0.75) within group (order by annual_mid)) as p75
from pay
-- Drops mislabelled intervals, e.g. an annual range tagged monthly ($1.3M) or hourly tagged yearly ($33)
where annual_mid between 15000 and 1000000
group by role_family
having count(*) >= 20
order by median desc
