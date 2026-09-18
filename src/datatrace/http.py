from concurrent.futures import ThreadPoolExecutor

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

USER_AGENT = "datatrace/0.1 (portfolio project; github.com/DhanushNagesh)"
TIMEOUT = 30


def make_session() -> requests.Session:
    retry = Retry(
        total=3,
        backoff_factor=1.0,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",),
        respect_retry_after_header=True,
    )
    session = requests.Session()
    session.headers["User-Agent"] = USER_AGENT
    session.mount("https://", HTTPAdapter(max_retries=retry))
    return session


def get_json(session: requests.Session, url: str, params: dict | None = None):
    resp = session.get(url, params=params, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()


def get_many(session: requests.Session, urls: list[str], workers: int = 8):
    """Fetch detail URLs concurrently, in order. A 404 yields None: the posting was
    taken down between the list call and the detail call."""

    def one(url):
        try:
            return get_json(session, url)
        except requests.HTTPError as exc:
            if exc.response is not None and exc.response.status_code == 404:
                return None
            raise

    with ThreadPoolExecutor(max_workers=workers) as pool:
        yield from pool.map(one, urls)
