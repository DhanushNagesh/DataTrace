from collections.abc import Iterator

from datatrace.http import get_json

BASE_URL = "https://api.ashbyhq.com/posting-api/job-board/{board}"


def fetch(session, board: str) -> Iterator[dict]:
    # One unpaginated call returns every posting with its full description
    data = get_json(
        session, BASE_URL.format(board=board), params={"includeCompensation": "true"}
    )
    yield from data["jobs"]
