from collections.abc import Iterator

from datatrace.http import get_json, get_many

BASE_URL = "https://ats.rippling.com/api/v2/board/{board}/jobs"
PAGE_SIZE = 100


def fetch(session, board: str) -> Iterator[dict]:
    url = BASE_URL.format(board=board)
    items, page_no = [], 0
    while True:
        page = get_json(session, url, params={"page": page_no, "pageSize": PAGE_SIZE})
        items.extend(page["items"])
        page_no += 1
        if page_no >= page["totalPages"]:
            break
    details = get_many(session, [f"{url}/{item['id']}" for item in items])
    for item, detail in zip(items, details):
        if detail is not None:
            # Only the list carries structured locations with country codes
            yield {**detail, "locations": item["locations"]}
