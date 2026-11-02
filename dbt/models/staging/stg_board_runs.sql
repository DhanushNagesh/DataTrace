{{ config(materialized='incremental', unique_key=['source', 'board', 'observed_at']) }}

-- Runs in which each board returned postings. A board that failed (or went empty) in a run has
-- no row for it, so "latest run" here is the latest run that actually saw the board.
-- Incremental on loaded_at rather than observed_at, so a run loaded late still gets picked up.
select
    source,
    board,
    ingested_at as observed_at,
    max(loaded_at) as loaded_at
from {{ source('raw', 'job_postings') }}
where {{ not_retired_board() }}
{% if is_incremental() %}
    and loaded_at > (select max(loaded_at) from {{ this }})
{% endif %}
group by 1, 2, 3
