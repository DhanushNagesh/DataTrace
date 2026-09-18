with src as (
    select * from {{ source('raw', 'job_postings') }}
    where source = 'rippling'
),

parsed as (
    select
        board,
        payload->>'uuid' as posting_id,
        payload->>'companyName' as company,
        payload->>'name' as title,
        (
            select string_agg(l->>'name', ' | ')
            from jsonb_array_elements(payload->'locations') l
        ) as location,
        payload->'locations' as locations,
        payload->'department'->>'name' as department,
        -- employmentType.id holds the readable label ("Salaried, full-time"), label holds the code
        payload->'employmentType'->>'id' as employment_type,
        -- Postings list several tiered ranges (US Tier 1/2/3, office, OTE); the first USD one is the top tier
        jsonb_path_query_first(payload, '$.payRangeDetails[*] ? (@.currency == "USD")') as pay,
        payload->>'url' as url,
        payload->'description'->>'role' as description_html,
        (payload->>'createdOn')::timestamptz as published_at,
        ingested_at as observed_at
    from src
)

select
    'rippling:' || board || ':' || posting_id as posting_key,
    'rippling' as source,
    board,
    posting_id,
    company,
    title,
    location,
    department,
    employment_type,
    locations @> '[{"workplaceType": "REMOTE"}]' as is_remote,
    locations @> '[{"countryCode": "US"}]' as is_us,
    false as is_remote_anywhere,
    (pay->>'rangeStart')::numeric as salary_min,
    (pay->>'rangeEnd')::numeric as salary_max,
    pay->>'currency' as salary_currency,
    {{ pay_interval("pay->>'frequency'") }} as salary_interval,
    url,
    description_html,
    published_at,
    null::timestamptz as source_updated_at,
    observed_at
from parsed
