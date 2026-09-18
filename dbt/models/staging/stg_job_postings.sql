-- US-accessible observations across sources (US location, or remote with no region restriction):
-- one row per posting per ingest run
{% set sources = ['stg_greenhouse__postings', 'stg_lever__postings', 'stg_remoteok__postings'] %}

{% for model in sources %}
select * from {{ ref(model) }} where is_us or is_remote_anywhere
{% if not loop.last %}union all{% endif %}
{% endfor %}
