import gzip
import json

import boto3
import pytest
from moto import mock_aws

from datatrace import load


def write_run(base, run, records, source="greenhouse", board="acme"):
    obj = base / f"source={source}/dt=2026-09-17/run={run}/{board}.jsonl"
    obj.parent.mkdir(parents=True, exist_ok=True)
    meta = {
        "source": source,
        "board": board,
        "ingested_at": "2026-09-17T08:00:00+00:00",
    }
    obj.write_text(
        "".join(
            json.dumps({**meta, "payload": r}, ensure_ascii=False) + "\n"
            for r in records
        )
    )
    manifest = base / f"_manifests/dt=2026-09-17/run={run}.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(
        json.dumps({"run_ts": "2026-09-17T08:00:00+00:00", "objects": [str(obj)]})
    )


def test_load_is_idempotent(conn, tmp_path):
    write_run(tmp_path, "080000", [{"id": 1}, {"id": 2}])
    store = load.LocalStore(tmp_path)
    assert load.load(conn, store) == {"runs": 1, "records": 2}
    assert load.load(conn, store) == {"runs": 0, "records": 0}
    assert conn.execute("select count(*) from raw.job_postings").fetchone()[0] == 2


def test_unicode_line_separator_stays_in_one_record(conn, tmp_path):
    write_run(tmp_path, "080000", [{"id": 1, "content": "a b"}])
    load.load(conn, load.LocalStore(tmp_path))
    row = conn.execute("select payload->>'content' from raw.job_postings").fetchone()
    assert row[0] == "a b"


def test_bad_record_rolls_back_whole_run(conn, tmp_path):
    write_run(tmp_path, "080000", [{"id": 1}])
    obj = next(tmp_path.rglob("*.jsonl"))
    obj.write_text(obj.read_text() + "{not json\n")
    with pytest.raises(json.JSONDecodeError):
        load.load(conn, load.LocalStore(tmp_path))
    conn.rollback()
    assert conn.execute("select count(*) from raw.job_postings").fetchone()[0] == 0
    assert conn.execute("select count(*) from raw.loaded_runs").fetchone()[0] == 0


@mock_aws
def test_s3_store_reads_gzipped_objects():
    s3 = boto3.client("s3", region_name="us-east-2")
    s3.create_bucket(
        Bucket="bkt", CreateBucketConfiguration={"LocationConstraint": "us-east-2"}
    )
    s3.put_object(
        Bucket="bkt", Key="raw/source=x/o.jsonl.gz", Body=gzip.compress(b'{"a": 1}\n')
    )
    s3.put_object(
        Bucket="bkt", Key="raw/_manifests/dt=2026-09-17/run=1.json", Body=b"{}"
    )
    store = load.S3Store("bkt", "raw", client=s3)
    assert store.manifests() == ["s3://bkt/raw/_manifests/dt=2026-09-17/run=1.json"]
    assert store.read("s3://bkt/raw/source=x/o.jsonl.gz") == b'{"a": 1}\n'
