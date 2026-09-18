with src as (
    select * from {{ source('raw', 'job_postings') }}
    where source = 'lever'
),

parsed as (
    select
        board,
        payload->>'id' as posting_id,
        payload->>'text' as title,
        payload->'categories'->>'location' as location,
        array_to_string(
            array(select jsonb_array_elements_text(payload->'categories'->'allLocations')), ' | '
        ) as all_locations,
        payload->>'country' as country_code,
        coalesce(payload->'categories'->>'department', payload->'categories'->>'team') as department,
        payload->'categories'->>'commitment' as employment_type,
        payload->>'workplaceType' as workplace_type,
        (payload->'salaryRange'->>'min')::numeric as salary_min,
        (payload->'salaryRange'->>'max')::numeric as salary_max,
        payload->'salaryRange'->>'currency' as salary_currency,
        payload->'salaryRange'->>'interval' as salary_interval,
        payload->>'hostedUrl' as url,
        payload->>'description' as description_html,
        to_timestamp((payload->>'createdAt')::bigint / 1000.0) as published_at,
        ingested_at as observed_at
    from src
)

select
    'lever:' || parsed.board || ':' || posting_id as posting_key,
    'lever' as source,
    parsed.board,
    posting_id,
    -- Lever postings carry no company name; fall back to the slug for boards missing from the seed
    coalesce(companies.company, initcap(parsed.board)) as company,
    title,
    location,
    department,
    employment_type,
    workplace_type = 'remote' as is_remote,
    -- country is the primary location only, so also check the full location list
    coalesce(country_code = 'US', false) or {{ is_us_location('all_locations') }} as is_us,
    country_code is null and {{ is_generic_remote('location') }} as is_remote_anywhere,
    salary_min,
    salary_max,
    salary_currency,
    salary_interval,
    url,
    description_html,
    published_at,
    null::timestamptz as source_updated_at,
    observed_at
from parsed
left join {{ ref('lever_companies') }} as companies on companies.board = parsed.board
