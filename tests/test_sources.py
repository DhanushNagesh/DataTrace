import gzip
import json
from datetime import UTC, datetime
from pathlib import Path

import boto3
import requests
from moto import mock_aws

from datatrace import http, writer
from datatrace.sources import ashby, lever, remoteok, rippling, smartrecruiters


def test_remoteok_skips_legal_notice(monkeypatch):
    payload = [{"legal": "terms"}, {"id": "1", "position": "Data Analyst"}]
    monkeypatch.setattr(remoteok, "get_json", lambda s, url: payload)
    assert list(remoteok.fetch(None)) == [{"id": "1", "position": "Data Analyst"}]


def test_lever_paginates_until_short_page(monkeypatch):
    pages = {0: [{"id": i} for i in range(100)], 100: [{"id": 100}]}
    monkeypatch.setattr(lever, "get_json", lambda s, url, params: pages[params["skip"]])
    assert len(list(lever.fetch(None, "acme"))) == 101


def test_ashby_yields_jobs(monkeypatch):
    monkeypatch.setattr(
        ashby, "get_json", lambda s, url, params: {"jobs": [{"id": "a"}]}
    )
    assert list(ashby.fetch(None, "acme")) == [{"id": "a"}]


def test_smartrecruiters_pages_then_fetches_details(monkeypatch):
    pages = {
        0: {"content": [{"id": i} for i in range(100)], "totalFound": 101},
        100: {"content": [{"id": 100}], "totalFound": 101},
    }
    monkeypatch.setattr(
        smartrecruiters, "get_json", lambda s, url, params: pages[params["offset"]]
    )
    # Posting 5 was taken down between the list and detail calls
    monkeypatch.setattr(
        smartrecruiters,
        "get_many",
        lambda s, urls: ({"url": u} if not u.endswith("/5") else None for u in urls),
    )
    details = list(smartrecruiters.fetch(None, "Acme"))
    assert len(details) == 100
    assert details[0]["url"].endswith("/companies/Acme/postings/0")


def test_rippling_merges_per_location_items(monkeypatch):
    items = [
        {"id": "j1", "locations": [{"name": "NYC"}]},
        {"id": "j1", "locations": [{"name": "SF"}]},
    ]
    monkeypatch.setattr(
        rippling, "get_json", lambda s, url, params: {"items": items, "totalPages": 1}
    )
    fetched = []

    def fake_many(s, urls):
        fetched.extend(urls)
        return [{"uuid": "j1", "name": "Eng"}]

    monkeypatch.setattr(rippling, "get_many", fake_many)
    assert list(rippling.fetch(None, "acme")) == [
        {"uuid": "j1", "name": "Eng", "locations": [{"name": "NYC"}, {"name": "SF"}]}
    ]
    assert len(fetched) == 1


class FakeSession:
    def __init__(self, statuses):
        self.statuses = statuses

    def get(self, url, params=None, timeout=None):
        resp = requests.Response()
        resp.status_code = self.statuses[url]
        resp._content = b'{"url": "%s"}' % url.encode()
        resp.url = url
        return resp


def test_get_many_keeps_order_and_skips_404():
    session = FakeSession({"a": 200, "b": 404, "c": 200})
    assert list(http.get_many(session, ["a", "b", "c"])) == [
        {"url": "a"},
        None,
        {"url": "c"},
    ]


def test_get_many_raises_on_server_error():
    session = FakeSession({"a": 200, "b": 500})
    try:
        list(http.get_many(session, ["a", "b"]))
    except requests.HTTPError:
        return
    raise AssertionError("expected HTTPError")


def test_failed_write_leaves_no_final_file(tmp_path):
    sink = writer.LocalSink(tmp_path)

    def boom():
        yield {"id": 1}
        raise RuntimeError("network died")

    try:
        sink.write_records("out", boom(), {"source": "x"})
    except RuntimeError:
        pass
    assert list(tmp_path.iterdir()) == []


def test_write_wraps_payload_with_meta(tmp_path):
    sink = writer.LocalSink(tmp_path)
    location, count = sink.write_records(
        "out", [{"id": 1}], {"source": "lever", "board": "acme"}
    )
    row = json.loads(Path(location).read_text())
    assert count == 1
    assert row == {"source": "lever", "board": "acme", "payload": {"id": 1}}


def test_raw_key_is_hive_partitioned():
    ts = datetime(2026, 9, 17, 8, 34, 29, tzinfo=UTC)
    assert (
        writer.raw_key("greenhouse", ts, "stripe")
        == "source=greenhouse/dt=2026-09-17/run=083429/stripe"
    )


@mock_aws
def test_s3_sink_uploads_gzipped_jsonl():
    client = boto3.client("s3", region_name="us-west-2")
    client.create_bucket(
        Bucket="bkt", CreateBucketConfiguration={"LocationConstraint": "us-west-2"}
    )
    sink = writer.S3Sink("bkt", "raw", client=client)
    location, count = sink.write_records("source=x/k", [{"id": 1}, {"id": 2}], {})

    assert location == "s3://bkt/raw/source=x/k.jsonl.gz"
    body = client.get_object(Bucket="bkt", Key="raw/source=x/k.jsonl.gz")["Body"].read()
    rows = [json.loads(line) for line in gzip.decompress(body).splitlines()]
    assert count == 2 and rows[1] == {"payload": {"id": 2}}


@mock_aws
def test_s3_sink_uploads_nothing_on_fetch_failure():
    client = boto3.client("s3", region_name="us-west-2")
    client.create_bucket(
        Bucket="bkt", CreateBucketConfiguration={"LocationConstraint": "us-west-2"}
    )

    def boom():
        yield {"id": 1}
        raise ValueError("bad json")

    try:
        writer.S3Sink("bkt", client=client).write_records("k", boom(), {})
    except ValueError:
        pass
    assert client.list_objects_v2(Bucket="bkt")["KeyCount"] == 0


def test_make_sink_parses_s3_uri(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-west-2")
    sink = writer.make_sink("s3://my-bucket/raw/")
    assert (sink.bucket, sink.prefix) == ("my-bucket", "raw")
