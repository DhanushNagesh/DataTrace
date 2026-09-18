with src as (
    select * from {{ source('raw', 'job_postings') }}
    where source = 'remoteok'
),

parsed as (
    select
        payload->>'id' as posting_id,
        payload->>'company' as company,
        payload->>'position' as title,
        nullif(trim(payload->>'location'), '') as location,
        -- 0 means not listed
        nullif((payload->>'salary_min')::numeric, 0) as salary_min,
        nullif((payload->>'salary_max')::numeric, 0) as salary_max,
        payload->>'url' as url,
        payload->>'description' as description_html,
        (payload->>'date')::timestamptz as published_at,
        ingested_at as observed_at
    from src
)

select
    'remoteok::' || posting_id as posting_key,
    'remoteok' as source,
    null::text as board,
    posting_id,
    company,
    title,
    location,
    null::text as department,
    null::text as employment_type,
    true as is_remote,
    {{ is_us_location('location') }} as is_us,
    -- RemoteOK is a remote-only board, so a blank location means unrestricted, same as "Worldwide"
    location is null or {{ is_generic_remote('location') }} as is_remote_anywhere,
    salary_min,
    salary_max,
    case when salary_min is not null or salary_max is not null then 'USD' end as salary_currency,
    case when salary_min is not null or salary_max is not null then 'year' end as salary_interval,
    url,
    description_html,
    published_at,
    null::timestamptz as source_updated_at,
    observed_at
from parsed
