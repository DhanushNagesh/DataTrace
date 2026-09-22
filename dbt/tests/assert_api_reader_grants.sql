-- Returns any relation where api_reader's access is wrong: a mart it can't read, or a raw/staging
-- relation it can. The API breaks, or leaks, the morning after a build that fails this.
-- depends_on: {{ ref('fct_job_postings') }}
-- depends_on: {{ ref('dim_companies') }}
-- depends_on: {{ ref('rpt_postings') }}
select table_schema, table_name
from information_schema.tables
where (
        table_schema = 'marts'
        and not (
            has_schema_privilege('api_reader', 'marts', 'usage')
            and has_table_privilege('api_reader', format('%I.%I', table_schema, table_name), 'select')
        )
    )
    or (
        table_schema in ('raw', 'staging', 'seeds')
        and has_table_privilege('api_reader', format('%I.%I', table_schema, table_name), 'select')
    )
