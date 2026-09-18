-- US-only observations across sources: one row per posting per ingest run
{% set sources = ['stg_greenhouse__postings', 'stg_lever__postings', 'stg_remoteok__postings'] %}

{% for model in sources %}
select * from {{ ref(model) }} where is_us
{% if not loop.last %}union all{% endif %}
{% endfor %}
