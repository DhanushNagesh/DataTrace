-- One row per hiring company across all sources. Keyed on the normalized name so the same company
-- on Greenhouse and RemoteOK collapses to one row.
select
    {{ company_key('company') }} as company_key,
    mode() within group (order by company) as company_name,
    string_agg(distinct source, ', ' order by source) as sources,
    min(observed_at) as first_seen_at
from {{ ref('stg_job_postings') }}
where company is not null
group by 1
