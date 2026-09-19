import argparse
import logging
import os
import sys
from pathlib import Path

import psycopg
from dotenv import load_dotenv

log = logging.getLogger("datatrace.export")

TABLES = ["rpt_postings"]

# Tableau's CSV reader types "true"/"false" as booleans but not Postgres's t/f, and doesn't
# parse the +00 offset on timestamptz. Timestamps go out as naive UTC.
CASTS = {
    "boolean": "{col}::text",
    "timestamp with time zone": "({col} at time zone 'UTC')::timestamp(0)",
}


def select_list(conn: psycopg.Connection, table: str) -> str:
    rows = conn.execute(
        """
        select column_name, data_type from information_schema.columns
        where table_schema = 'marts' and table_name = %s
        order by ordinal_position
        """,
        (table,),
    ).fetchall()
    if not rows:
        raise RuntimeError(f"marts.{table} not found; run dbt build first")
    cols = []
    for name, dtype in rows:
        cast = CASTS.get(dtype)
        cols.append(f"{cast.format(col=name)} as {name}" if cast else name)
    return ", ".join(cols)


def export(conn: psycopg.Connection, out_dir: Path) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    counts = {}
    for table in TABLES:
        path = out_dir / f"{table}.csv"
        # Write to a temp file so a failed export never leaves Tableau a half-written CSV
        tmp = path.with_suffix(".csv.tmp")
        with conn.cursor() as cur, tmp.open("wb") as f:
            with cur.copy(
                f"copy (select {select_list(conn, table)} from marts.{table} order by 1) "
                "to stdout with (format csv, header)"
            ) as copy:
                for chunk in copy:
                    f.write(chunk)
            counts[table] = cur.rowcount
        tmp.replace(path)
        log.info("%s: %d rows -> %s", table, counts[table], path)
    return counts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Export reporting marts to CSV for Tableau"
    )
    parser.add_argument("--out", default="exports", help="directory to write CSVs to")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    load_dotenv()
    with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
        export(conn, Path(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
