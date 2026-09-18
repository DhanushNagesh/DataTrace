{% macro company_key(expr) -%}
    md5(lower(trim({{ expr }})))
{%- endmacro %}
