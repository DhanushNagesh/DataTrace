import logging
import os
import tomllib

from datatrace.ingest import run
from datatrace.writer import make_sink

# Lambda installs its own root handler before import, so basicConfig would be a no-op
logging.getLogger().setLevel(logging.INFO)
log = logging.getLogger("datatrace.lambda")


def handler(event, context):
    with open(os.environ.get("DATATRACE_CONFIG", "config/boards.toml"), "rb") as f:
        boards_config = tomllib.load(f)
    sink = make_sink(os.environ["DATATRACE_OUT"])

    # Manual test invokes can pass {"sources": ["remoteok"]}; scheduled runs send no sources
    sources = set((event or {}).get("sources") or []) or None
    summary = run(boards_config, sink, sources)

    # Partial failure is normal (a board renames its token) and already logged per board.
    # Raise only when nothing landed so the invocation counts as an error in CloudWatch.
    if not summary["ok"]:
        raise RuntimeError(f"every source failed: {summary['failed']}")

    return {
        "run_ts": summary["run_ts"],
        "records": sum(summary["ok"].values()),
        "ok": len(summary["ok"]),
        "failed": summary["failed"],
    }
