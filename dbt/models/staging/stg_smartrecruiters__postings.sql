with src as (
    select * from {{ source('raw', 'job_postings') }}
    where source = 'smartrecruiters'
),

parsed as (
    select
        board,
        payload->>'id' as posting_id,
        payload->'company'->>'name' as company,
        payload->>'name' as title,
        payload->'location'->>'fullLocation' as location,
        lower(payload->'location'->>'country') as country_code,
        (payload->'location'->>'remote')::boolean as is_remote_flag,
        coalesce(payload->'department'->>'label', payload->'function'->>'label') as department,
        payload->'typeOfEmployment'->>'label' as employment_type,
        payload->>'postingUrl' as url,
        -- companyDescription is the same boilerplate on every posting, so it's left out
        concat_ws(
            E'\n',
            payload->'jobAd'->'sections'->'jobDescription'->>'text',
            payload->'jobAd'->'sections'->'qualifications'->>'text',
            payload->'jobAd'->'sections'->'additionalInformation'->>'text'
        ) as description_html,
        (payload->>'releasedDate')::timestamptz as published_at,
        ingested_at as observed_at
    from src
)

select
    'smartrecruiters:' || board || ':' || posting_id as posting_key,
    'smartrecruiters' as source,
    board,
    posting_id,
    company,
    title,
    location,
    department,
    employment_type,
    coalesce(is_remote_flag, false) as is_remote,
    coalesce(country_code = 'us', false) as is_us,
    country_code is null and coalesce(is_remote_flag, false) as is_remote_anywhere,
    null::numeric as salary_min,
    null::numeric as salary_max,
    null::text as salary_currency,
    null::text as salary_interval,
    url,
    description_html,
    published_at,
    null::timestamptz as source_updated_at,
    observed_at
from parsed
