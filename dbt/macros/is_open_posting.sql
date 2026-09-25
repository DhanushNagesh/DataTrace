{#
  The one definition of "open": still present in the board's latest run, and not past the
  staleness cutoff. RemoteOK's is_active is null because its feed is a rolling window, so
  absence there says nothing about closing; null counts as open.

  This lives in a macro because it did not: rpt_seniority_mix kept its own copy of the
  is_active test, missed the staleness clause when that was added, and reported 766 more
  postings than the headline count on the same page.
#}
{% macro is_open_posting(alias='') -%}
{%- set p = alias ~ '.' if alias else '' -%}
    {{ p }}is_active is not false and not {{ p }}is_stale
{%- endmacro %}
