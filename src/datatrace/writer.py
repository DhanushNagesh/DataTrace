import json
from datetime import datetime
from pathlib import Path


def raw_path(
    base: Path, source: str, run_ts: datetime, board: str | None = None
) -> Path:
    name = f"{board}.jsonl" if board else f"{source}.jsonl"
    return (
        base
        / f"source={source}"
        / f"dt={run_ts:%Y-%m-%d}"
        / f"run={run_ts:%H%M%S}"
        / name
    )


def write_jsonl(path: Path, records, meta: dict) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".jsonl.tmp")
    count = 0
    with tmp.open("w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps({**meta, "payload": record}, ensure_ascii=False))
            f.write("\n")
            count += 1
    # Rename only after a full write so a crash never leaves a half file that looks complete
    tmp.replace(path)
    return count
