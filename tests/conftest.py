import os

import psycopg
import pytest

ADMIN_URL = os.environ.get(
    "TEST_ADMIN_DATABASE_URL",
    "postgresql://datatrace:datatrace@localhost:5432/datatrace",
)


@pytest.fixture
def conn():
    try:
        admin = psycopg.connect(ADMIN_URL, autocommit=True, connect_timeout=2)
    except psycopg.OperationalError:
        pytest.skip("local Postgres not running (docker compose up -d)")
    with admin:
        if not admin.execute(
            "select 1 from pg_database where datname = 'datatrace_test'"
        ).fetchone():
            admin.execute("create database datatrace_test")
    url = psycopg.conninfo.make_conninfo(ADMIN_URL, dbname="datatrace_test")
    with psycopg.connect(url) as c:
        c.execute("drop schema if exists raw cascade")
        c.commit()
        yield c
