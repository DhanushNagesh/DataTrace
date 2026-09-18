{# Normalise each source's pay period spelling (per-year-salary, 1 YEAR, YEAR, ...) to year/month/week/day/hour #}
{% macro pay_interval(expr) -%}
    case
        when {{ expr }} ~* 'year|annual' then 'year'
        when {{ expr }} ~* 'month' then 'month'
        when {{ expr }} ~* 'week' then 'week'
        when {{ expr }} ~* 'day|daily' then 'day'
        when {{ expr }} ~* 'hour' then 'hour'
    end
{%- endmacro %}
