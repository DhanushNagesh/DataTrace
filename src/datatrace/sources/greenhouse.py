from collections.abc import Iterator

from datatrace.http import get_json

BASE_URL = "https://boards-api.greenhouse.io/v1/boards/{board}/jobs"


def fetch(session, board: str) -> Iterator[dict]:
    # content=true includes the HTML description; the endpoint is not paginated
    data = get_json(session, BASE_URL.format(board=board), params={"content": "true"})
    yield from data["jobs"]
