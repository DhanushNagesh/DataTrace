from collections.abc import Iterator

from datatrace.http import get_json

# The feed is the most recent ~100 jobs with no pagination or date parameter, so this returns
# 99 rows every run no matter how long it has been collecting. There is nothing to page through.
URL = "https://remoteok.com/api"


def fetch(session) -> Iterator[dict]:
    data = get_json(session, URL)
    # First element is a legal/terms notice, not a job
    yield from (item for item in data if "id" in item)
