{# Display label for a seniority value. Shared by every mart so the levels read the same everywhere. #}
{% macro seniority_label(expr) -%}
    case {{ expr }}
        when 'intern' then 'Intern'
        when 'entry' then 'Entry'
        when 'mid' then 'Mid'
        when 'senior' then 'Senior'
        when 'staff_plus' then 'Staff+'
        when 'director_plus' then 'Director+'
        when 'unspecified' then 'Unspecified'
    end
{%- endmacro %}

{#
  Sort order for seniority, 1 (intern) to 7 (unspecified, which sorts last). Both Tableau and the
  API order levels by this: alphabetical would put Entry before Intern and Staff+ before Senior.
#}
{% macro seniority_rank(expr) -%}
    array_position(
        array['intern', 'entry', 'mid', 'senior', 'staff_plus', 'director_plus', 'unspecified'],
        {{ expr }}
    )
{%- endmacro %}
