with src as (
    select * from {{ source('raw', 'job_postings') }}
    where source = 'ashby'
),

parsed as (
    select
        board,
        payload->>'id' as posting_id,
        payload->>'title' as title,
        payload->>'location' as location,
        concat_ws(
            ' | ',
            payload->>'location',
            (
                select string_agg(l->>'location', ' | ')
                from jsonb_array_elements(payload->'secondaryLocations') l
            )
        ) as all_locations,
        (
            select array_agg(distinct c)
            from (
                select payload->'address'->'postalAddress'->>'addressCountry' as c
                union all
                select l->'address'->'postalAddress'->>'addressCountry'
                from jsonb_array_elements(payload->'secondaryLocations') l
            ) countries
            where c is not null
        ) as countries,
        payload->>'department' as department,
        payload->>'employmentType' as employment_type,
        payload->>'workplaceType' as workplace_type,
        (payload->>'isRemote')::boolean as is_remote_flag,
        jsonb_path_query_first(
            payload, '$.compensation.summaryComponents[*] ? (@.compensationType == "Salary")'
        ) as salary,
        payload->>'jobUrl' as url,
        payload->>'descriptionHtml' as description_html,
        (payload->>'publishedAt')::timestamptz as published_at,
        ingested_at as observed_at
    from src
    where coalesce((payload->>'isListed')::boolean, true)
)

select
    'ashby:' || parsed.board || ':' || posting_id as posting_key,
    'ashby' as source,
    parsed.board,
    posting_id,
    coalesce(companies.company, initcap(parsed.board)) as company,
    title,
    location,
    department,
    employment_type,
    -- isRemote is true when any location is remote (hybrid NYC with a remote option), so prefer
    -- workplaceType and only fall back to isRemote when it's blank
    coalesce(workplace_type = 'Remote', is_remote_flag, false) as is_remote,
    countries && array['United States', 'USA', 'US'] or {{ is_us_location('all_locations') }} as is_us,
    countries is null and {{ is_generic_remote('location') }} as is_remote_anywhere,
    (salary->>'minValue')::numeric as salary_min,
    (salary->>'maxValue')::numeric as salary_max,
    salary->>'currencyCode' as salary_currency,
    {{ pay_interval("salary->>'interval'") }} as salary_interval,
    url,
    description_html,
    published_at,
    null::timestamptz as source_updated_at,
    observed_at
from parsed
left join {{ ref('board_companies') }} as companies
    on companies.source = 'ashby' and companies.board = parsed.board
