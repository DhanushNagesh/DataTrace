"""Runs bundled SQL scripts against the warehouse.

RDS has no public address, so admin SQL can't be run from a laptop. This Lambda sits in the VPC
and applies scripts from infra/, which ship in its zip. It is invoked by hand, not on a schedule.
"""

import logging
import os
from pathlib import Path

from datatrace.db import connect

logging.getLogger().setLevel(logging.INFO)
log = logging.getLogger("datatrace.db_admin")

SQL_DIR = Path(os.environ.get("DATATRACE_SQL_DIR", "sql"))
DEFAULT_SCRIPTS = ["db_roles.sql"]


def resolve(name: str) -> Path:
    # Scripts come from the zip, never from the event: an invoke may only pick a bundled file
    if name not in {p.name for p in SQL_DIR.glob("*.sql")}:
        raise ValueError(f"unknown script: {name}")
    return SQL_DIR / name


def handler(event, context):
    scripts = (event or {}).get("scripts") or DEFAULT_SCRIPTS
    paths = [resolve(name) for name in scripts]

    applied = []
    rows = None
    # One transaction for all of them: a script that fails halfway leaves the database unchanged
    with connect() as conn:
        for path in paths:
            cur = conn.execute(path.read_text())
            # Rows from the last statement come back in the response, so check scripts can
            # report what the database looks like from inside the VPC
            if cur.description:
                rows = [
                    dict(zip([c.name for c in cur.description], r))
                    for r in cur.fetchall()
                ]
            log.info("applied %s", path.name)
            applied.append(path.name)
    return {"applied": applied, "rows": rows}
