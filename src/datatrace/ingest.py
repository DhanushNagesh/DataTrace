import argparse
import logging
import sys
import tomllib
from datetime import UTC, datetime
from pathlib import Path

import requests

from datatrace.http import make_session
from datatrace.sources import greenhouse, lever, remoteok
from datatrace.writer import raw_path, write_jsonl

log = logging.getLogger("datatrace.ingest")

BOARD_SOURCES = {"greenhouse": greenhouse.fetch, "lever": lever.fetch}
FEED_SOURCES = {"remoteok": remoteok.fetch}


def build_jobs(boards_config: dict):
    for source, fetch in BOARD_SOURCES.items():
        for board in boards_config.get(source, []):
            yield source, board, lambda s, f=fetch, b=board: f(s, b)
    for source, fetch in FEED_SOURCES.items():
        yield source, None, fetch


def run(boards_config: dict, out_dir: Path, sources: set[str] | None = None) -> dict:
    session = make_session()
    run_ts = datetime.now(UTC)
    summary = {"ok": {}, "failed": {}}

    for source, board, fetch in build_jobs(boards_config):
        if sources and source not in sources:
            continue
        key = f"{source}/{board}" if board else source
        meta = {
            "source": source,
            "board": board,
            "ingested_at": run_ts.isoformat(),
        }
        path = raw_path(out_dir, source, run_ts, board)
        try:
            count = write_jsonl(path, fetch(session), meta)
        except (requests.RequestException, KeyError, ValueError) as exc:
            # One dead board (renamed token, API outage) should not sink the whole run
            log.error("failed %s: %s", key, exc)
            path.with_suffix(".jsonl.tmp").unlink(missing_ok=True)
            summary["failed"][key] = str(exc)
            continue
        log.info("wrote %d records for %s -> %s", count, key, path)
        summary["ok"][key] = count

    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Pull raw job postings to local storage"
    )
    parser.add_argument("--config", type=Path, default=Path("config/boards.toml"))
    parser.add_argument("--out", type=Path, default=Path("data/raw"))
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

    summary = run(boards_config, args.out, set(args.source) if args.source else None)
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
