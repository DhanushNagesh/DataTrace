-- Seniority mix within each role family: each row is a share of its own family, not of all postings
with labelled as (
    select
        {{ role_family_label('role_family') }} as role_family,
        {{ seniority_label('seniority') }} as seniority,
        {{ seniority_rank('seniority') }} as seniority_rank
    from {{ ref('fct_job_postings') }}
    where {{ is_open_posting() }}
)

select
    role_family,
    seniority,
    seniority_rank,
    count(*) as postings,
    round(100.0 * count(*) / sum(count(*)) over (partition by role_family), 1) as pct_of_family
from labelled
group by role_family, seniority, seniority_rank
order by role_family, seniority_rank
