import psycopg
import pytest

from datatrace import db_admin


@pytest.fixture
def sql_dir(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(db_admin, "SQL_DIR", tmp_path)
    # The real connection is a context manager that would close the fixture's connection
    monkeypatch.setattr(db_admin, "connect", lambda: _KeepOpen(conn))
    return tmp_path


class _KeepOpen:
    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self.conn

    def __exit__(self, exc_type, *_):
        if exc_type is None:
            self.conn.commit()
        else:
            self.conn.rollback()


def test_applies_requested_scripts_in_order(sql_dir, conn):
    (sql_dir / "a.sql").write_text("drop table if exists t; create table t (n int);")
    (sql_dir / "b.sql").write_text("insert into t values (1), (2);")

    result = db_admin.handler({"scripts": ["a.sql", "b.sql"]}, None)

    assert result == {"applied": ["a.sql", "b.sql"], "rows": None}
    assert conn.execute("select count(*) from t").fetchone()[0] == 2


def test_failure_rolls_back_every_script(sql_dir, conn):
    (sql_dir / "ok.sql").write_text("drop table if exists t2; create table t2 (n int);")
    (sql_dir / "bad.sql").write_text("select nonexistent_function();")

    with pytest.raises(psycopg.Error):
        db_admin.handler({"scripts": ["ok.sql", "bad.sql"]}, None)

    conn.rollback()
    assert not conn.execute("select to_regclass('t2')").fetchone()[0]


@pytest.mark.parametrize("name", ["../db_roles.sql", "/etc/passwd", "missing.sql"])
def test_rejects_scripts_not_in_the_bundle(sql_dir, name):
    with pytest.raises(ValueError):
        db_admin.handler({"scripts": [name]}, None)


def test_returns_rows_from_the_last_statement(sql_dir, conn):
    (sql_dir / "check.sql").write_text("select 1 as n, 'x' as label;")

    result = db_admin.handler({"scripts": ["check.sql"]}, None)

    assert result["rows"] == [{"n": 1, "label": "x"}]
