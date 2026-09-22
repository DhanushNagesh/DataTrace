-- Where rows are lost between raw and the marts. Read-only.
select 'raw' as stage, source, count(*) as rows, count(distinct object_key) as objects,
       min(ingested_at)::date as first_run, max(ingested_at)::date as last_run
from raw.job_postings group by 2
union all
select 'staging', source, count(*), null, min(observed_at)::date, max(observed_at)::date
from staging.stg_job_postings group by 2
union all
select 'marts', source, count(*), null, min(first_seen_at)::date, max(last_seen_at)::date
from marts.rpt_postings group by 2
order by 1 desc, 2
