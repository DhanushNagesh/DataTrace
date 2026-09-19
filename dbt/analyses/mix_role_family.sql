-- Share of open postings by role family, with how much of each bucket is remote and shows pay.
-- pct_with_salary mostly tracks source mix (Greenhouse and SmartRecruiters never publish pay), not role.
select
    role_family,
    count(*) as postings,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_all,
    round(100.0 * avg(is_remote::int), 1) as pct_remote,
    round(100.0 * count(salary_min) / count(*), 1) as pct_with_salary
from {{ ref('fct_job_postings') }}
where is_active is not false
group by role_family
order by postings desc
