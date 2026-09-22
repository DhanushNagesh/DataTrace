import json

import pytest
from psycopg.rows import dict_row

from datatrace import api


@pytest.fixture
def marts(conn, monkeypatch):
    conn.row_factory = dict_row
    conn.execute("drop schema if exists marts cascade")
    conn.execute("create schema marts")
    conn.execute(
        """
        create table marts.rpt_postings (
            posting_key text, source text, company_name text, title text, role_family text,
            seniority text, work_mode text, location text, salary_annual_mid_usd numeric,
            url text, first_seen_at timestamptz, is_open boolean, data_as_of timestamptz
        );
        insert into marts.rpt_postings values
            ('a', 'lever', 'Acme', 'Data Engineer', 'Data Engineering', 'Mid', 'Remote (US)',
             'Remote', 150000, 'https://a', '2026-09-17', true, '2026-09-18'),
            ('b', 'greenhouse', 'Beta', 'Account Executive', 'Sales & Success', 'Senior',
             'On-site / hybrid', 'NYC', null, 'https://b', '2026-08-01', true, '2026-09-18'),
            ('c', 'greenhouse', 'Beta', 'Data Analyst', 'Data Analytics', 'Entry',
             'On-site / hybrid', 'NYC', null, 'https://c', '2026-08-01', false, '2026-09-18');
        """
    )
    monkeypatch.setattr(api, "get_conn", lambda: conn)
    return conn


def call(route, params=None):
    res = api.handler({"routeKey": route, "queryStringParameters": params}, None)
    return res["statusCode"], json.loads(res["body"])


def test_stats(marts):
    status, body = call("GET /stats")
    assert status == 200
    assert body == {
        "open_postings": 2,
        "new_this_week": 1,
        "companies": 2,
        "sources": 2,
        "data_as_of": "2026-09-18T00:00:00+00:00",
    }


def test_postings_filters_and_excludes_closed(marts):
    _, body = call("GET /postings")
    assert [p["posting_key"] for p in body["postings"]] == ["a", "b"]

    _, body = call("GET /postings", {"q": "data"})
    assert [p["posting_key"] for p in body["postings"]] == ["a"]
    assert body["postings"][0]["salary_annual_mid_usd"] == 150000

    _, body = call("GET /postings", {"work_mode": "On-site / hybrid", "limit": "1"})
    assert [p["posting_key"] for p in body["postings"]] == ["b"]


def test_postings_treats_input_as_data(marts):
    status, body = call("GET /postings", {"q": "' or 1=1 --"})
    assert status == 200
    assert body["postings"] == []


@pytest.mark.parametrize("params", [{"limit": "500"}, {"limit": "x"}, {"q": "a" * 101}])
def test_postings_rejects_bad_params(marts, params):
    status, body = call("GET /postings", params)
    assert status == 400
    assert "error" in body


def test_unknown_route_is_404():
    status, _ = call("GET /admin")
    assert status == 404
