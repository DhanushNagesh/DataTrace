-- One row: the headline counts and freshness stamp for the dashboard header. Same query the API
-- used to run per request; doing it here means a visitor reads one row instead of scanning every posting.
select
    count(*) filter (where is_open) as open_postings,
    -- Counted on the board's own publish date, not first_seen_at. first_seen_at is when our
    -- ingest first saw the row, so every posting from a young warehouse looks new and this
    -- headline read 11,285 of 11,285. coalesce matches what the board's NEW badge does for a
    -- source that gives no date, so the count and the badges can't disagree.
    count(*) filter (
        where is_open
          and coalesce(published_at, first_seen_at) >= data_as_of - interval '7 days'
    ) as new_this_week,
    count(distinct company_name) filter (where is_open) as companies,
    count(distinct source) as sources,
    max(data_as_of) as data_as_of
from {{ ref('rpt_postings') }}
