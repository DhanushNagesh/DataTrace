import datetime as dt
import json
import logging
from decimal import Decimal

import psycopg
from psycopg.rows import dict_row

from datatrace import db

logging.getLogger().setLevel(logging.INFO)
log = logging.getLogger("datatrace.api")

MAX_LIMIT = 100
MAX_QUERY_LEN = 100

# Module scope survives between invocations on a warm Lambda, so the connection is reused
# instead of paying a TLS + auth handshake on every request.
_conn: psycopg.Connection | None = None


class BadRequest(Exception):
    pass


def get_conn() -> psycopg.Connection:
    global _conn
    if _conn is None or _conn.closed:
        # autocommit so a failed query can't leave a warm connection stuck in an aborted transaction
        _conn = db.connect(autocommit=True, row_factory=dict_row)
    return _conn


def stats(conn: psycopg.Connection, params: dict) -> dict:
    # marts.rpt_stats is a single pre-aggregated row. Returned unwrapped, unlike the list routes below.
    return conn.execute("select * from marts.rpt_stats").fetchone()


def mart(table: str, order_by: str):
    # Each of these marts is a few dozen to a few hundred rows, pre-aggregated once a day by dbt,
    # so the route is just a select with no per-request aggregation and no query params. table and
    # order_by are the literals passed below, never request input, so the f-string is safe here.
    def handler(conn: psycopg.Connection, params: dict) -> dict:
        rows = conn.execute(
            f"select * from marts.{table} order by {order_by}"
        ).fetchall()
        return {table.removeprefix("rpt_"): rows}

    handler.table = table
    return handler


def int_param(params: dict, name: str, default: int, maximum: int) -> int:
    raw = params.get(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError:
        raise BadRequest(f"{name} must be an integer")
    if not 0 <= value <= maximum:
        raise BadRequest(f"{name} must be between 0 and {maximum}")
    return value


# Whitelist: the value picked here becomes SQL text, so a request can only choose an ordering,
# never write one.
#
# Date sorts run on published_at, the date the board itself gives the posting, not first_seen_at,
# which is only when our ingest first saw the row and is the same value for every row until the
# warehouse has several runs behind it. Boards that give no date sort last rather than claiming
# to be the newest or the oldest.
#
# Every sort ends on md5(posting_key) rather than posting_key itself. The tiebreaker has to be
# deterministic or paging repeats and skips rows, but posting_key is 'source:board:id', so
# ordering by it groups a whole company together — with a constant leading key the sort falls
# through entirely and the first page is two companies. Hashing keeps the determinism and drops
# the clustering.
SORTS = {
    "newest": "published_at desc nulls last, md5(posting_key)",
    "oldest": "published_at nulls last, md5(posting_key)",
    "salary_high": "salary_annual_mid_usd desc nulls last, md5(posting_key)",
    "salary_low": "salary_annual_mid_usd, md5(posting_key)",
    "company": "company_name, first_seen_at desc, md5(posting_key)",
}


def postings(conn: psycopg.Connection, params: dict) -> dict:
    q = (params.get("q") or "").strip()
    if len(q) > MAX_QUERY_LEN:
        raise BadRequest(f"q must be at most {MAX_QUERY_LEN} characters")
    company = (params.get("company") or "").strip()
    if len(company) > MAX_QUERY_LEN:
        raise BadRequest(f"company must be at most {MAX_QUERY_LEN} characters")
    limit = int_param(params, "limit", 25, MAX_LIMIT)
    offset = int_param(params, "offset", 0, 10_000)
    min_salary = int_param(params, "min_salary", 0, 1_000_000)

    sort = params.get("sort") or "newest"
    if sort not in SORTS:
        raise BadRequest(f"sort must be one of {', '.join(SORTS)}")

    # count(*) over () totals the filtered set in the same scan the page comes from, so the
    # browser can say how many roles matched without a second query.
    rows = conn.execute(
        f"""
        select posting_key, source, company_name, title, role_family, seniority, work_mode,
               location, salary_annual_mid_usd, url, published_at, first_seen_at, days_listed,
               count(*) over () as total
        from marts.rpt_postings
        where is_open
          and (%(q)s::text is null or title ilike %(pattern)s or company_name ilike %(pattern)s)
          and (%(role_family)s::text is null or role_family = %(role_family)s)
          and (%(seniority)s::text is null or seniority = %(seniority)s)
          and (%(work_mode)s::text is null or work_mode = %(work_mode)s)
          and (%(source)s::text is null or source = %(source)s)
          and (%(company)s::text is null or company_name ilike %(company_pattern)s)
          and (%(min_salary)s = 0 or salary_annual_mid_usd >= %(min_salary)s)
        order by {SORTS[sort]}
        limit %(limit)s offset %(offset)s
        """,
        {
            "q": q or None,
            "pattern": f"%{q}%",
            "role_family": params.get("role_family"),
            "seniority": params.get("seniority"),
            "work_mode": params.get("work_mode"),
            "source": params.get("source"),
            "company": company or None,
            "company_pattern": f"%{company}%",
            "min_salary": min_salary,
            "limit": limit,
            "offset": offset,
        },
    ).fetchall()

    total = rows[0].pop("total") if rows else 0
    for row in rows[1:]:
        del row["total"]
    return {"postings": rows, "total": total, "limit": limit, "offset": offset}


# Keys are API Gateway route keys. Gateway only forwards routes it has configured,
# so this table and the Gateway routes must list the same endpoints.
ROUTES = {
    "GET /stats": stats,
    "GET /postings": postings,
    "GET /role-mix": mart("rpt_role_mix", "postings desc"),
    "GET /seniority-mix": mart("rpt_seniority_mix", "role_family, seniority_rank"),
    "GET /salary-by-role": mart("rpt_salary_by_role", "median desc"),
    "GET /time-to-close": mart("rpt_time_to_close", "median_days"),
    "GET /daily-flow": mart("rpt_daily_flow", "role_family, day"),
}


def to_json(value):
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, (dt.datetime, dt.date)):
        return value.isoformat()
    raise TypeError(f"cannot serialise {type(value).__name__}")


def response(status: int, body: dict, cache_seconds: int = 0) -> dict:
    headers = {"content-type": "application/json"}
    if cache_seconds:
        headers["cache-control"] = f"public, max-age={cache_seconds}"
    return {
        "statusCode": status,
        "headers": headers,
        "body": json.dumps(body, default=to_json),
    }


def handler(event, context):
    route = ROUTES.get(event.get("routeKey"))
    if route is None:
        return response(404, {"error": "not found"})
    try:
        # The data only changes once a day, so let browsers and Vercel cache for 5 minutes
        return response(
            200, route(get_conn(), event.get("queryStringParameters") or {}), 300
        )
    except BadRequest as e:
        return response(400, {"error": str(e)})
    except Exception:
        # Log the real error, but never return SQL or stack traces to the caller
        log.exception("request failed: %s", event.get("routeKey"))
        # The connection may be what broke; start fresh on the next request
        global _conn
        if _conn is not None:
            _conn.close()
        _conn = None
        return response(500, {"error": "internal error"})
