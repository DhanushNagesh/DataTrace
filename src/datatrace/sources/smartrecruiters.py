from collections.abc import Iterator

from datatrace.http import get_json, get_many

BASE_URL = "https://api.smartrecruiters.com/v1/companies/{board}/postings"
PAGE_SIZE = 100


def fetch(session, board: str) -> Iterator[dict]:
    url = BASE_URL.format(board=board)
    postings, offset = [], 0
    while True:
        page = get_json(session, url, params={"limit": PAGE_SIZE, "offset": offset})
        postings.extend(page["content"])
        offset += PAGE_SIZE
        if not page["content"] or offset >= page["totalFound"]:
            break
    # Offset paging over a live list: a posting added mid-run shifts every later page by one,
    # so the last posting of one page comes back as the first of the next
    ids = dict.fromkeys(p["id"] for p in postings)
    # The list omits the job ad text, so each posting needs its own detail request
    details = get_many(session, [f"{url}/{i}" for i in ids])
    yield from (d for d in details if d is not None)
