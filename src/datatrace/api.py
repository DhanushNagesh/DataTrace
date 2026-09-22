import datetime as dt
import json
import logging
import os
from decimal import Decimal

import psycopg
from psycopg.rows import dict_row

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
        _conn = psycopg.connect(
            os.environ["DATABASE_URL"], autocommit=True, row_factory=dict_row
        )
    return _conn


def stats(conn: psycopg.Connection, params: dict) -> dict:
    return conn.execute(
        """
        select
            count(*) filter (where is_open) as open_postings,
            count(*) filter (where first_seen_at >= data_as_of - interval '7 days') as new_this_week,
            count(distinct company_name) filter (where is_open) as companies,
            count(distinct source) as sources,
            max(data_as_of) as data_as_of
        from marts.rpt_postings
        """
    ).fetchone()


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
