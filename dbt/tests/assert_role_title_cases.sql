-- Returns the hand-labelled titles the role_family or seniority macros get wrong
select
    title,
    expected_role_family,
    {{ role_family('title') }} as actual_role_family,
    expected_seniority,
    {{ seniority('title') }} as actual_seniority
from {{ ref('role_title_cases') }}
where {{ role_family('title') }} != expected_role_family
    or {{ seniority('title') }} != expected_seniority
