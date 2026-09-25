-- Flat, one-row-per-posting table for Tableau: fct_job_postings with the company name, readable
-- labels and annualised pay joined on, so the workbook needs no joins or calculated business rules.
with postings as (
    select
        f.*,
        c.company_name,
        (f.salary_min + coalesce(f.salary_max, f.salary_min)) / 2
            * case f.salary_interval
                when 'year' then 1
                when 'month' then 12
                when 'week' then 52
                when 'day' then 260
                when 'hour' then 2080
            end as annual_mid
    from {{ ref('fct_job_postings') }} f
    join {{ ref('dim_companies') }} c using (company_key)
)

select
    posting_key,
    source,
    company_name,
    title,
    {{ role_family_label('role_family') }} as role_family,
    role_family in ('data_engineering', 'data_science_ml', 'data_analytics') as is_data_role,
    {{ seniority_label('seniority') }} as seniority,
    {{ seniority_rank('seniority') }} as seniority_rank,
    case
        when is_remote_anywhere then 'Remote (anywhere)'
        when is_remote then 'Remote (US)'
        else 'On-site / hybrid'
    end as work_mode,
    location,
    department,
    -- Same 15k-1M band as analyses: outside it the interval is mislabelled, e.g. annual tagged monthly
    case
        when salary_currency = 'USD' and salary_min > 0 and annual_mid between 15000 and 1000000
            then round(annual_mid)
    end as salary_annual_mid_usd,
    url,
    published_at,
    first_seen_at,
    last_seen_at,
    -- RemoteOK is_active is null (rolling feed); the analyses count those as open, and so does this
    is_active is not false and not is_stale as is_open,
    is_stale,
    round(days_listed::numeric, 1) as days_listed,
    (select max(observed_at) from {{ ref('stg_board_runs') }}) as data_as_of
from postings
