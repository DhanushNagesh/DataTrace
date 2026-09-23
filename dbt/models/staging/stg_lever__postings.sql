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
        to_timestamp((payload->>'createdAt')::bigint / 1000.0) as created_at,
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
    {{ pay_interval('salary_interval') }} as salary_interval,
    url,
    description_html,
    -- createdAt is the only date Lever's payload carries, and on a board that migrated onto
    -- Lever the old requisitions were backfilled with a date but no time: every Palantir
    -- createdAt before 2015 lands on exactly 00:00:00 UTC, every one after it carries a real
    -- time. Those are migration stamps rather than publish dates, and one of them reaches the
    -- marts as a 4,600-day listing, so they are dropped and published_at falls back to
    -- first_seen_at downstream. Same idea as the 15k-1M salary band in rpt_postings: a value
    -- outside the plausible shape means the field is holding something other than what it says.
    case
        when created_at >= '2015-01-01'::timestamptz then created_at
        when created_at::time <> '00:00:00' then created_at
    end as published_at,
    null::timestamptz as source_updated_at,
    observed_at
from parsed
left join {{ ref('board_companies') }} as companies
    on companies.source = 'lever' and companies.board = parsed.board
