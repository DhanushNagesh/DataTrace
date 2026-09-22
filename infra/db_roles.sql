-- Creates the API's read-only login role. Safe to rerun. Run as the database owner:
--   docker compose exec -T postgres psql -U datatrace -d datatrace -v ON_ERROR_STOP=1 < infra/db_roles.sql
-- Table and schema grants come from dbt (dbt_project.yml), because dbt recreates the tables.

do $$
begin
    if not exists (select from pg_roles where rolname = 'api_reader') then
        create role api_reader login;
    end if;
    -- rds_iam only exists on RDS; it switches the role to IAM token auth, so it never has a password there
    if exists (select from pg_roles where rolname = 'rds_iam') then
        grant rds_iam to api_reader;
    end if;
end
$$;

-- Session defaults applied at login. The missing write privileges are the real guard; these stop
-- a runaway query or a leaked-connection pileup from hurting the pipeline sharing this instance.
alter role api_reader set default_transaction_read_only = on;
alter role api_reader set statement_timeout = '5s';
alter role api_reader set idle_in_transaction_session_timeout = '30s';
alter role api_reader connection limit 10;
