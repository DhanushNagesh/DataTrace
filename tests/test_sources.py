import json

from datatrace import writer
from datatrace.sources import lever, remoteok


def test_remoteok_skips_legal_notice(monkeypatch):
    payload = [{"legal": "terms"}, {"id": "1", "position": "Data Analyst"}]
    monkeypatch.setattr(remoteok, "get_json", lambda s, url: payload)
    assert list(remoteok.fetch(None)) == [{"id": "1", "position": "Data Analyst"}]


def test_lever_paginates_until_short_page(monkeypatch):
    pages = {0: [{"id": i} for i in range(100)], 100: [{"id": 100}]}
    monkeypatch.setattr(lever, "get_json", lambda s, url, params: pages[params["skip"]])
    assert len(list(lever.fetch(None, "acme"))) == 101


def test_failed_write_leaves_no_final_file(tmp_path):
    path = tmp_path / "out.jsonl"

    def boom():
        yield {"id": 1}
        raise RuntimeError("network died")

    try:
        writer.write_jsonl(path, boom(), {"source": "x"})
    except RuntimeError:
        pass
    assert not path.exists()


def test_write_wraps_payload_with_meta(tmp_path):
    path = tmp_path / "out.jsonl"
    writer.write_jsonl(path, [{"id": 1}], {"source": "lever", "board": "acme"})
    row = json.loads(path.read_text())
    assert row == {"source": "lever", "board": "acme", "payload": {"id": 1}}
