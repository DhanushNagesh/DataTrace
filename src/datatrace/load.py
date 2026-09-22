import argparse
import gzip
import json
import logging
import os
import sys
from pathlib import Path

from psycopg.types.json import Jsonb

from datatrace.db import connect

log = logging.getLogger("datatrace.load")

DDL = """
create schema if not exists raw;

create table if not exists raw.loaded_runs (
    manifest_key text primary key,
    run_ts timestamptz not null,
    records integer not null,
    loaded_at timestamptz not null default now()
);

create table if not exists raw.job_postings (
    source text not null,
    board text,
    ingested_at timestamptz not null,
    object_key text not null,
    line_no integer not null,
    payload jsonb not null,
    loaded_at timestamptz not null default now(),
    primary key (object_key, line_no)
);
"""


class LocalStore:
    def __init__(self, base: Path):
        self.base = base

    def manifests(self) -> list[str]:
        return sorted(str(p) for p in (self.base / "_manifests").rglob("*.json"))

    def read(self, location: str) -> bytes:
        data = Path(location).read_bytes()
        return gzip.decompress(data) if location.endswith(".gz") else data


class S3Store:
    def __init__(self, bucket: str, prefix: str = "", client=None):
        if client is None:
            import boto3

            client = boto3.client("s3")
        self.client = client
        self.bucket = bucket
        self.prefix = prefix.strip("/")

    def manifests(self) -> list[str]:
        prefix = f"{self.prefix}/_manifests/" if self.prefix else "_manifests/"
        keys = []
        for page in self.client.get_paginator("list_objects_v2").paginate(
            Bucket=self.bucket, Prefix=prefix
        ):
            keys.extend(o["Key"] for o in page.get("Contents", []))
        return sorted(f"s3://{self.bucket}/{k}" for k in keys if k.endswith(".json"))

    def read(self, location: str) -> bytes:
        bucket, _, key = location.removeprefix("s3://").partition("/")
        data = self.client.get_object(Bucket=bucket, Key=key)["Body"].read()
        return gzip.decompress(data) if key.endswith(".gz") else data


def make_store(src: str) -> LocalStore | S3Store:
    if src.startswith("s3://"):
        bucket, _, prefix = src.removeprefix("s3://").partition("/")
        return S3Store(bucket, prefix)
    return LocalStore(Path(src))


def _rows(store, objects: list[str]):
    for obj in objects:
        # Not splitlines(): it also breaks on U+2028 etc., which ensure_ascii=False leaves raw in descriptions
        lines = store.read(obj).decode("utf-8").rstrip("\n").split("\n")
        for line_no, line in enumerate(lines, 1):
            rec = json.loads(line)
            yield (
                rec["source"],
                rec["board"],
                rec["ingested_at"],
                obj,
                line_no,
                Jsonb(rec["payload"]),
            )


def load_run(conn, store, manifest_key: str) -> int:
    manifest = json.loads(store.read(manifest_key))
    count = 0
    # One transaction per run: a crash mid-load leaves no rows and no loaded_runs entry, so the
    # next load retries the whole run. A concurrent double-load fails on the primary keys.
    with conn.transaction(), conn.cursor() as cur:
        with cur.copy(
            "copy raw.job_postings (source, board, ingested_at, object_key, line_no, payload)"
            " from stdin"
        ) as copy:
            for row in _rows(store, manifest["objects"]):
                copy.write_row(row)
                count += 1
        cur.execute(
            "insert into raw.loaded_runs (manifest_key, run_ts, records) values (%s, %s, %s)",
            (manifest_key, manifest["run_ts"], count),
        )
    return count


def load(conn, store) -> dict:
    conn.execute(DDL)
    conn.commit()
    loaded = {r[0] for r in conn.execute("select manifest_key from raw.loaded_runs")}
    pending = [m for m in store.manifests() if m not in loaded]
    summary = {"runs": 0, "records": 0}
    for manifest_key in pending:
        count = load_run(conn, store, manifest_key)
        log.info("loaded %d records from %s", count, manifest_key)
        summary["runs"] += 1
        summary["records"] += count
    return summary


def handler(event, context):
    # Same DATATRACE_OUT the ingest Lambda writes to: S3 is the handoff between the two
    with connect() as conn:
        summary = load(conn, make_store(os.environ["DATATRACE_OUT"]))
    log.info("loaded %d runs, %d records", summary["runs"], summary["records"])
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Load finished raw runs into Postgres")
    parser.add_argument(
        "--src",
        default=os.environ.get("DATATRACE_OUT", "data/raw"),
        help="local directory or s3://bucket/prefix the ingest wrote to",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    # CLI only; the Lambda zip ships neither dotenv nor a .env file
    from dotenv import load_dotenv

    load_dotenv()
    with connect() as conn:
        summary = load(conn, make_store(args.src))
    log.info("done: %d new runs, %d records", summary["runs"], summary["records"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
