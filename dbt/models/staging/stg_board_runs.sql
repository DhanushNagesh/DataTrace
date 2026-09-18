-- Runs in which each board returned postings. A board that failed (or went empty) in a run has
-- no row for it, so "latest run" here is the latest run that actually saw the board.
select distinct
    source,
    board,
    ingested_at as observed_at
from {{ source('raw', 'job_postings') }}
