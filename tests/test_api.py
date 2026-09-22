import json

import pytest
from psycopg.rows import dict_row

from datatrace import api

# Column types and label spellings mirror what dbt actually builds (see dbt/models/marts). Fixtures
# invented by hand drifted from the real marts once already: they used display labels for models
# that emit raw enum values, and the tests passed while the API served the wrong thing.
MARTS = """
create table marts.rpt_postings (
    posting_key text, source text, company_name text, title text, role_family text,
    seniority text, work_mode text, location text, salary_annual_mid_usd numeric,
    url text, first_seen_at timestamptz, is_open boolean, days_listed numeric,
    data_as_of timestamptz
);
insert into marts.rpt_postings values
    ('a', 'lever', 'Acme', 'Data Engineer', 'Data Engineering', 'Mid', 'Remote (US)',
     'Remote', 150000, 'https://a', '2026-09-17', true, 3.0, '2026-09-18'),
    ('b', 'greenhouse', 'Beta', 'Account Executive', 'Sales & Success', 'Senior',
     'On-site / hybrid', 'NYC', 90000, 'https://b', '2026-08-01', true, 48.0, '2026-09-18'),
    ('c', 'greenhouse', 'Beta', 'Data Analyst', 'Data Analytics', 'Entry',
     'On-site / hybrid', 'NYC', null, 'https://c', '2026-08-01', false, 48.0, '2026-09-18');

create table marts.rpt_stats (
    open_postings bigint, new_this_week bigint, companies bigint, sources bigint,
    data_as_of timestamptz
);
insert into marts.rpt_stats values (2, 1, 2, 2, '2026-09-18');

create table marts.rpt_role_mix (
    role_family text, postings bigint, pct_of_all numeric, pct_remote numeric,
    pct_with_salary numeric
);
insert into marts.rpt_role_mix values
    ('Sales & Success', 66, 40.0, 10.0, 5.0),
    ('Data Engineering', 100, 60.0, 80.0, 40.0);

create table marts.rpt_seniority_mix (
    role_family text, seniority text, seniority_rank integer, postings bigint,
    pct_of_family numeric
);
insert into marts.rpt_seniority_mix values
    ('Data Engineering', 'Senior', 4, 60, 60.0),
    ('Data Engineering', 'Intern', 1, 40, 40.0);

create table marts.rpt_salary_by_role (
    role_family text, n bigint, sources text, p25 double precision,
    median double precision, p75 double precision
);
insert into marts.rpt_salary_by_role values
    ('Data Analytics', 25, 'lever', 90000, 110000, 130000),
    ('Data Engineering', 40, 'lever, ashby', 120000, 150000, 180000);

create table marts.rpt_time_to_close (
    role_family text, closed_postings bigint, median_days numeric, p90_days numeric
);
insert into marts.rpt_time_to_close values
    ('Sales & Success', 12, 30.0, 60.0),
    ('Data Engineering', 20, 14.0, 45.0);

create table marts.rpt_daily_flow (
    day date, role_family text, open_postings bigint, opened bigint, closed bigint,
    wow_change bigint
);
insert into marts.rpt_daily_flow values
    ('2026-09-18', 'Data Engineering', 103, 4, 1, null),
    ('2026-09-17', 'Data Engineering', 100, 5, 2, 10);
"""


@pytest.fixture
def marts(conn, monkeypatch):
    conn.row_factory = dict_row
    conn.execute("drop schema if exists marts cascade")
    conn.execute("create schema marts")
    conn.execute(MARTS)
    monkeypatch.setattr(api, "get_conn", lambda: conn)
    return conn


def call(route, params=None):
    res = api.handler({"routeKey": route, "queryStringParameters": params}, None)
    return res["statusCode"], json.loads(res["body"])


def test_stats_reads_the_single_prebuilt_row(marts):
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


def test_postings_filters_on_every_facet(marts):
    for params, expected in [
        ({"seniority": "Mid"}, ["a"]),
        ({"source": "greenhouse"}, ["b"]),
        ({"company": "acm"}, ["a"]),
        ({"min_salary": "100000"}, ["a"]),
        ({"role_family": "Data Engineering", "min_salary": "200000"}, []),
    ]:
        _, body = call("GET /postings", params)
        assert [p["posting_key"] for p in body["postings"]] == expected, params


def test_postings_total_counts_the_filtered_set_not_the_page(marts):
    # Two rows match but only one is returned, and the count still describes the whole match
    _, body = call("GET /postings", {"limit": "1"})
    assert len(body["postings"]) == 1
    assert body["total"] == 2
    assert "total" not in body["postings"][0]

    _, body = call("GET /postings", {"q": "nothing matches this"})
    assert body["total"] == 0


def test_postings_sorts_only_by_a_known_key(marts):
    _, body = call("GET /postings", {"sort": "salary_high"})
    assert [p["posting_key"] for p in body["postings"]] == ["a", "b"]

    _, body = call("GET /postings", {"sort": "company"})
    assert [p["posting_key"] for p in body["postings"]] == ["a", "b"]

    status, body = call(
        "GET /postings", {"sort": "first_seen_at; drop table marts.rpt_postings"}
    )
    assert status == 400


def test_postings_treats_input_as_data(marts):
    status, body = call("GET /postings", {"q": "' or 1=1 --"})
    assert status == 200
    assert body["postings"] == []


@pytest.mark.parametrize("params", [{"limit": "500"}, {"limit": "x"}, {"q": "a" * 101}])
def test_postings_rejects_bad_params(marts, params):
    status, body = call("GET /postings", params)
    assert status == 400
    assert "error" in body


MART_ROUTES = [r for r, fn in api.ROUTES.items() if hasattr(fn, "table")]


@pytest.mark.parametrize("route", MART_ROUTES)
def test_every_mart_route_serves_its_mart(marts, route):
    # Fails loudly if a route is added without a matching fixture table, rather than 500ing in prod
    status, body = call(route)
    assert status == 200
    (rows,) = body.values()
    assert rows, f"{route} returned no rows"


def test_mart_routes_are_ordered_for_display(marts):
    _, body = call("GET /role-mix")
    assert [r["postings"] for r in body["role_mix"]] == [100, 66]

    # Seniority sorts by level, not by how common the level is: Intern (40) before Senior (60)
    _, body = call("GET /seniority-mix")
    assert [r["seniority"] for r in body["seniority_mix"]] == ["Intern", "Senior"]

    _, body = call("GET /salary-by-role")
    assert [r["median"] for r in body["salary_by_role"]] == [150000, 110000]

    _, body = call("GET /time-to-close")
    assert [r["median_days"] for r in body["time_to_close"]] == [14.0, 30.0]

    _, body = call("GET /daily-flow")
    assert [r["day"] for r in body["daily_flow"]] == ["2026-09-17", "2026-09-18"]


def test_unknown_route_is_404():
    status, _ = call("GET /admin")
    assert status == 404
