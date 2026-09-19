-- Seniority mix within each role family: each row is a share of its own family, not of all postings
select
    role_family,
    seniority,
    count(*) as postings,
    round(100.0 * count(*) / sum(count(*)) over (partition by role_family), 1) as pct_of_family
from {{ ref('fct_job_postings') }}
where is_active is not false
group by role_family, seniority
order by role_family, postings desc
