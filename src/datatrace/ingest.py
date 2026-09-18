import argparse
import logging
import os
import sys
import tomllib
from datetime import UTC, datetime
from pathlib import Path

import requests
from botocore.exceptions import BotoCoreError, ClientError

from datatrace.http import make_session
from datatrace.sources import (
    ashby,
    greenhouse,
    lever,
    remoteok,
    rippling,
    smartrecruiters,
)
from datatrace.writer import make_sink, manifest_key, raw_key

log = logging.getLogger("datatrace.ingest")

BOARD_SOURCES = {
    "greenhouse": greenhouse.fetch,
    "lever": lever.fetch,
    "ashby": ashby.fetch,
    "smartrecruiters": smartrecruiters.fetch,
    "rippling": rippling.fetch,
}
FEED_SOURCES = {"remoteok": remoteok.fetch}


def build_jobs(boards_config: dict):
    for source, fetch in BOARD_SOURCES.items():
        for board in boards_config.get(source, []):
            yield source, board, lambda s, f=fetch, b=board: f(s, b)
    for source, fetch in FEED_SOURCES.items():
        yield source, None, fetch


def run(boards_config: dict, sink, sources: set[str] | None = None) -> dict:
    session = make_session()
    run_ts = datetime.now(UTC)
    summary = {"run_ts": run_ts.isoformat(), "ok": {}, "failed": {}, "objects": []}

    for source, board, fetch in build_jobs(boards_config):
        if sources and source not in sources:
            continue
        name = f"{source}/{board}" if board else source
        meta = {
            "source": source,
            "board": board,
            "ingested_at": run_ts.isoformat(),
        }
        try:
            location, count = sink.write_records(
                raw_key(source, run_ts, board), fetch(session), meta
            )
        except (requests.RequestException, KeyError, ValueError) as exc:
            # One dead board (renamed token, API outage) should not sink the whole run
            log.error("failed %s: %s", name, exc)
            summary["failed"][name] = str(exc)
            continue
        log.info("wrote %d records for %s -> %s", count, name, location)
        summary["ok"][name] = count
        summary["objects"].append(location)

    # Written last: its presence marks the run as finished for the downstream loader
    location = sink.write_json(manifest_key(run_ts), summary)
    log.info("manifest -> %s", location)
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Pull raw job postings to local disk or S3"
    )
    parser.add_argument("--config", type=Path, default=Path("config/boards.toml"))
    parser.add_argument(
        "--out",
        default=os.environ.get("DATATRACE_OUT", "data/raw"),
        help="local directory or s3://bucket/prefix",
    )
    parser.add_argument(
        "--source",
        action="append",
        choices=[*BOARD_SOURCES, *FEED_SOURCES],
        help="limit to one or more sources (repeatable)",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    with args.config.open("rb") as f:
        boards_config = tomllib.load(f)

    sink = make_sink(args.out)
    try:
        summary = run(boards_config, sink, set(args.source) if args.source else None)
    except (BotoCoreError, ClientError) as exc:
        # S3 auth/bucket errors hit every board identically, so fail fast instead of per-board
        log.error("storage error: %s", exc)
        return 2
    total = sum(summary["ok"].values())
    log.info(
        "done: %d records, %d ok, %d failed",
        total,
        len(summary["ok"]),
        len(summary["failed"]),
    )
    return 1 if summary["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
