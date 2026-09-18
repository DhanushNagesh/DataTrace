{# Location that says remote with no region attached: "Remote", "Worldwide", "Remote - Anywhere" #}
{% macro is_generic_remote(expr) -%}
    coalesce(
        trim({{ expr }}) ~* '^(remote|worldwide|anywhere|global)(\s*[-,/(]\s*(worldwide|anywhere|global)\)?)?$',
        false
    )
{%- endmacro %}
