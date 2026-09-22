-- Annualised USD salary midpoints by role family. Greenhouse and SmartRecruiters never publish pay,
-- so this describes companies on Ashby, Lever, Rippling and RemoteOK, not the whole sample.
select
    role_family,
    count(*) as n,
    string_agg(distinct source, ', ') as sources,
    round(percentile_cont(0.25) within group (order by salary_annual_mid_usd)) as p25,
    round(percentile_cont(0.5) within group (order by salary_annual_mid_usd)) as median,
    round(percentile_cont(0.75) within group (order by salary_annual_mid_usd)) as p75
from {{ ref('rpt_postings') }}
where is_open and salary_annual_mid_usd is not null
group by role_family
having count(*) >= 20
order by median desc
