from collections.abc import Iterator

from datatrace.http import get_json

BASE_URL = "https://api.lever.co/v0/postings/{board}"
PAGE_SIZE = 100


def fetch(session, board: str) -> Iterator[dict]:
    skip = 0
    while True:
        page = get_json(
            session,
            BASE_URL.format(board=board),
            params={"mode": "json", "limit": PAGE_SIZE, "skip": skip},
        )
        yield from page
        if len(page) < PAGE_SIZE:
            return
        skip += PAGE_SIZE
