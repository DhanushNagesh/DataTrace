import csv

from datatrace import export


def test_export_writes_tableau_friendly_csv(conn, tmp_path, monkeypatch):
    conn.execute("drop schema if exists marts cascade")
    conn.execute("create schema marts")
    conn.execute(
        """
        create table marts.t (key text, is_open boolean, seen_at timestamptz, note text);
        insert into marts.t values
            ('b', false, '2026-09-18 07:45:54.48+00', null),
            ('a', true, '2026-09-18 00:30:00-07', 'line one
        line two, with comma');
        """
    )
    monkeypatch.setattr(export, "TABLES", ["t"])

    counts = export.export(conn, tmp_path)

    with (tmp_path / "t.csv").open(newline="") as f:
        rows = list(csv.DictReader(f))
    assert counts == {"t": 2}
    assert [r["key"] for r in rows] == ["a", "b"]
    assert rows[0]["is_open"] == "true"
    assert rows[0]["seen_at"] == "2026-09-18 07:30:00"
    assert rows[1]["note"] == ""
    assert not list(tmp_path.glob("*.tmp"))
