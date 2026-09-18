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
    # The list repeats a job once per location, so merge those before fetching details
    locations: dict[str, list] = {}
    for item in items:
        locations.setdefault(item["id"], []).extend(item["locations"])
    details = get_many(session, [f"{url}/{job_id}" for job_id in locations])
    for job_id, detail in zip(locations, details):
        if detail is not None:
            # Only the list carries structured locations with country codes
            yield {**detail, "locations": locations[job_id]}
