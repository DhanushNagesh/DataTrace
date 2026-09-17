from collections.abc import Iterator

from datatrace.http import get_json

URL = "https://remoteok.com/api"


def fetch(session) -> Iterator[dict]:
    data = get_json(session, URL)
    # First element is a legal/terms notice, not a job
    yield from (item for item in data if "id" in item)
