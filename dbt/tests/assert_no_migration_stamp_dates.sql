-- A publish date that is both implausibly old and lands on exactly midnight UTC is a migration
-- stamp, not a publish date: a board that moved onto a new ATS backfills old requisitions with a
-- date and no time. stg_lever__postings drops the ones we know about; this fails the build if the
-- pattern turns up in another source, because days_listed measures from published_at and a single
-- decade-old stamp is enough to move a role family's p90 in rpt_time_to_close.
select posting_key, source, published_at, days_listed
from {{ ref('fct_job_postings') }}
where published_at < '2015-01-01'::timestamptz
  and published_at::time = '00:00:00'
