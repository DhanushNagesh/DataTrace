-- One row: the headline counts and freshness stamp for the dashboard header. Same query the API
-- used to run per request; doing it here means a visitor reads one row instead of scanning every posting.
select
    count(*) filter (where is_open) as open_postings,
    count(*) filter (where is_open and first_seen_at >= data_as_of - interval '7 days')
        as new_this_week,
    count(distinct company_name) filter (where is_open) as companies,
    count(distinct source) as sources,
    max(data_as_of) as data_as_of
from {{ ref('rpt_postings') }}
