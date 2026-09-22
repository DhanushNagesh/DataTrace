-- Reports what api_reader can actually do. Read-only; run through the migrations Lambda:
--   infra/db_admin.sh '{"scripts":["check_roles.sql"]}'
select
    r.rolname,
    r.rolcanlogin as can_login,
    r.rolconnlimit as connection_limit,
    r.rolconfig as session_settings,
    exists (
        select from pg_auth_members m
        join pg_roles g on g.oid = m.roleid
        where m.member = r.oid and g.rolname = 'rds_iam'
    ) as uses_iam_auth,
    -- null until dbt has built the marts schema in this database
    (select has_schema_privilege(r.rolname, 'marts', 'usage')
     where to_regnamespace('marts') is not null) as can_use_marts,
    has_database_privilege(r.rolname, current_database(), 'connect') as can_connect,
    has_database_privilege(r.rolname, current_database(), 'create') as can_create,
    (select count(*) from information_schema.tables where table_schema = 'marts') as marts_tables
from pg_roles r
where r.rolname in ('api_reader', 'datatrace_pipeline', 'datatrace_admin')
order by r.rolname
