with src as (
    select * from {{ source('raw', 'job_postings') }}
    where source = 'greenhouse'
),

parsed as (
    select
        board,
        payload->>'id' as posting_id,
        payload->>'company_name' as company,
        payload->>'title' as title,
        payload->'location'->>'name' as location,
        payload->'departments'->0->>'name' as department,
        payload->>'employment' as employment_type,
        jsonb_path_query_first(
            payload, '$.metadata[*] ? (@.name == "Workplace Type").value'
        ) #>> '{}' as workplace_type,
        payload->>'absolute_url' as url,
        payload->>'content' as description_html,
        (payload->>'first_published')::timestamptz as published_at,
        (payload->>'updated_at')::timestamptz as source_updated_at,
        ingested_at as observed_at
    from src
)

select
    'greenhouse:' || board || ':' || posting_id as posting_key,
    'greenhouse' as source,
    board,
    posting_id,
    company,
    title,
    location,
    department,
    employment_type,
    coalesce(workplace_type ilike 'remote%' or location ~* '\yremote\y', false) as is_remote,
    {{ is_us_location('location') }} as is_us,
    null::numeric as salary_min,
    null::numeric as salary_max,
    null::text as salary_currency,
    null::text as salary_interval,
    url,
    description_html,
    published_at,
    source_updated_at,
    observed_at
from parsed
