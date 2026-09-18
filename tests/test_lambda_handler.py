import pytest

from datatrace import ingest, lambda_handler


@pytest.fixture
def env(tmp_path, monkeypatch):
    config = tmp_path / "boards.toml"
    config.write_text('greenhouse = ["acme"]\nlever = []\n')
    monkeypatch.setenv("DATATRACE_CONFIG", str(config))
    monkeypatch.setenv("DATATRACE_OUT", str(tmp_path / "raw"))
    monkeypatch.setitem(ingest.FEED_SOURCES, "remoteok", lambda s: [{"id": "r1"}])
    return tmp_path


def test_handler_returns_summary(env, monkeypatch):
    monkeypatch.setitem(ingest.BOARD_SOURCES, "greenhouse", lambda s, b: [{"id": 1}])
    result = lambda_handler.handler({}, None)
    assert result["records"] == 2
    assert result["failed"] == {}
    assert list((env / "raw" / "_manifests").rglob("*.json"))


def test_handler_filters_sources_from_event(env, monkeypatch):
    monkeypatch.setitem(ingest.BOARD_SOURCES, "greenhouse", lambda s, b: [{"id": 1}])
    result = lambda_handler.handler({"sources": ["remoteok"]}, None)
    assert result["ok"] == 1


def test_handler_tolerates_partial_failure(env, monkeypatch):
    def dead_board(session, board):
        raise KeyError("jobs")

    monkeypatch.setitem(ingest.BOARD_SOURCES, "greenhouse", dead_board)
    result = lambda_handler.handler({}, None)
    assert result["failed"] == {"greenhouse/acme": "'jobs'"}


def test_handler_raises_when_nothing_lands(env, monkeypatch):
    def dead(*args):
        raise ValueError("bad json")

    monkeypatch.setitem(ingest.BOARD_SOURCES, "greenhouse", dead)
    monkeypatch.setitem(ingest.FEED_SOURCES, "remoteok", dead)
    with pytest.raises(RuntimeError, match="every source failed"):
        lambda_handler.handler({}, None)
