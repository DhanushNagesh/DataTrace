-- Returns the hand-labelled locations the US classifier gets wrong
select location, expected_is_us, {{ is_us_location('location') }} as actual_is_us
from {{ ref('us_location_cases') }}
where {{ is_us_location('location') }} != expected_is_us
