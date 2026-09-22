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
        rows = conn.execute(f"select * from marts.{table} order by {order_by}").fetchall()
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


def postings(conn: psycopg.Connection, params: dict) -> dict:
    q = (params.get("q") or "").strip()
    if len(q) > MAX_QUERY_LEN:
        raise BadRequest(f"q must be at most {MAX_QUERY_LEN} characters")
    limit = int_param(params, "limit", 25, MAX_LIMIT)
    offset = int_param(params, "offset", 0, 10_000)

    # Every filter is a bound parameter; a null parameter switches its filter off.
    # User input never becomes part of the SQL text.
    rows = conn.execute(
        """
        select posting_key, company_name, title, role_family, seniority, work_mode,
               location, salary_annual_mid_usd, url, first_seen_at
        from marts.rpt_postings
        where is_open
          and (%(q)s::text is null or title ilike %(pattern)s or company_name ilike %(pattern)s)
          and (%(role_family)s::text is null or role_family = %(role_family)s)
          and (%(work_mode)s::text is null or work_mode = %(work_mode)s)
        order by first_seen_at desc, posting_key
        limit %(limit)s offset %(offset)s
        """,
        {
            "q": q or None,
            "pattern": f"%{q}%",
            "role_family": params.get("role_family"),
            "work_mode": params.get("work_mode"),
            "limit": limit,
            "offset": offset,
        },
    ).fetchall()
    return {"postings": rows, "limit": limit, "offset": offset}


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
