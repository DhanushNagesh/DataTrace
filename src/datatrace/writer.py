import gzip
import io
import json
from datetime import datetime
from pathlib import Path


def raw_key(source: str, run_ts: datetime, board: str | None = None) -> str:
    name = board or source
    return f"source={source}/dt={run_ts:%Y-%m-%d}/run={run_ts:%H%M%S}/{name}"


def manifest_key(run_ts: datetime) -> str:
    # Underscore prefix keeps manifests out of source= partition globs
    return f"_manifests/dt={run_ts:%Y-%m-%d}/run={run_ts:%H%M%S}.json"


def _lines(records, meta: dict):
    for record in records:
        yield json.dumps({**meta, "payload": record}, ensure_ascii=False) + "\n"


class LocalSink:
    def __init__(self, base: Path):
        self.base = base

    def write_records(self, key: str, records, meta: dict) -> tuple[str, int]:
        path = self.base / f"{key}.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".jsonl.tmp")
        count = 0
        try:
            with tmp.open("w", encoding="utf-8") as f:
                for line in _lines(records, meta):
                    f.write(line)
                    count += 1
        except BaseException:
            tmp.unlink(missing_ok=True)
            raise
        # Rename only after a full write so a crash never leaves a half file that looks complete
        tmp.replace(path)
        return str(path), count

    def write_json(self, key: str, obj: dict) -> str:
        path = self.base / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(obj, indent=2))
        return str(path)


class S3Sink:
    def __init__(self, bucket: str, prefix: str = "", client=None):
        if client is None:
            import boto3

            client = boto3.client("s3")
        self.client = client
        self.bucket = bucket
        self.prefix = prefix.strip("/")

    def _full_key(self, key: str) -> str:
        return f"{self.prefix}/{key}" if self.prefix else key

    def write_records(self, key: str, records, meta: dict) -> tuple[str, int]:
        # Buffer fully before uploading: a fetch that dies mid-stream uploads nothing.
        # Largest board is ~8MB raw / <1MB gzipped, so memory is not a concern.
        buf = io.BytesIO()
        count = 0
        with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as gz:
            for line in _lines(records, meta):
                gz.write(line.encode("utf-8"))
                count += 1
        full_key = self._full_key(f"{key}.jsonl.gz")
        self.client.put_object(
            Bucket=self.bucket,
            Key=full_key,
            Body=buf.getvalue(),
            ContentType="application/gzip",
        )
        return f"s3://{self.bucket}/{full_key}", count

    def write_json(self, key: str, obj: dict) -> str:
        full_key = self._full_key(key)
        self.client.put_object(
            Bucket=self.bucket,
            Key=full_key,
            Body=json.dumps(obj, indent=2).encode("utf-8"),
            ContentType="application/json",
        )
        return f"s3://{self.bucket}/{full_key}"


def make_sink(out: str) -> LocalSink | S3Sink:
    if out.startswith("s3://"):
        bucket, _, prefix = out.removeprefix("s3://").partition("/")
        return S3Sink(bucket, prefix)
    return LocalSink(Path(out))
