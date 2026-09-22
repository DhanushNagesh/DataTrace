-- What the loader has landed so far. Read-only.
select
    (select count(*) from raw.loaded_runs) as runs_recorded,
    (select count(*) from raw.job_postings) as rows_loaded,
    (select count(distinct object_key) from raw.job_postings) as objects_loaded,
    (select string_agg(manifest_key, ' ' order by manifest_key) from raw.loaded_runs) as manifests
