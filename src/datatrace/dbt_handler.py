"""Runs dbt inside Lambda, against the prod (RDS) target.

dbt and its dependencies are far too large for a zip, so this ships as a container image.
The dbt project is baked into the image; the only runtime input is which command to run.
"""

import logging
import os
import threading
from concurrent.futures import ThreadPoolExecutor

from datatrace.rds_auth import token_from_env

logging.getLogger().setLevel(logging.INFO)
log = logging.getLogger("datatrace.dbt")

PROJECT_DIR = os.environ.get("DBT_PROJECT_DIR", "/var/task/dbt")
DEFAULT_COMMAND = ["build"]
# Commands that only read or rebuild the warehouse. Anything else (run-operation, for instance)
# would let an invoke run arbitrary SQL as the owner of every table.
ALLOWED = {
    "build",
    "run",
    "test",
    "seed",
    "snapshot",
    "compile",
    "deps",
    "debug",
    "parse",
}


class _ThreadLockContext:
    """Multiprocessing context whose locks are thread locks.

    Lambda has no /dev/shm, so creating a POSIX semaphore fails with FileNotFoundError. dbt asks
    its mp context for the adapter's lock but runs models in threads, so a thread lock is equivalent.
    """

    def __init__(self, wrapped):
        self._wrapped = wrapped

    def RLock(self):
        return threading.RLock()

    def Lock(self):
        return threading.Lock()

    def __getattr__(self, name):
        return getattr(self._wrapped, name)


class _ThreadPool:
    """Stand-in for dbt's DbtThreadPool, which subclasses multiprocessing.pool.ThreadPool.

    That pool builds a SimpleQueue guarded by POSIX semaphores, which Lambda can't create.
    dbt only ever runs its nodes in threads, so a ThreadPoolExecutor does the same work.
    """

    def __init__(self, processes, initializer=None, initargs=()):
        self.max_threads = processes
        self.max_microbatch_models = max(1, processes // 2)
        self.closed = False
        self._pool = ThreadPoolExecutor(
            max_workers=processes,
            initializer=initializer,
            initargs=tuple(initargs or ()),
        )

    def apply_async(self, func, args=(), kwds=None, callback=None):
        future = self._pool.submit(func, *args, **(kwds or {}))
        if callback is not None:
            future.add_done_callback(lambda f: callback(f.result()))
        return future

    def close(self):
        self.closed = True

    def is_closed(self):
        return self.closed

    def terminate(self):
        self._pool.shutdown(wait=False, cancel_futures=True)

    def join(self):
        self._pool.shutdown(wait=True)


def _use_thread_locks() -> None:
    """Replaces dbt's process-based primitives with thread equivalents."""
    # Patched before dbt.cli.main is imported: dbt.parser.manifest does
    # `from dbt.mp_context import get_mp_context`, capturing the name at import time
    from dbt import mp_context

    real = mp_context.get_mp_context
    mp_context.get_mp_context = lambda: _ThreadLockContext(real())

    from dbt.graph import thread_pool

    thread_pool.DbtThreadPool = _ThreadPool


def handler(event, context):
    command = (event or {}).get("command") or DEFAULT_COMMAND
    if not command or command[0] not in ALLOWED:
        raise ValueError(f"command not allowed: {command}")

    # profiles.yml's prod target reads DBT_*; every Lambda here is configured with DB_*.
    # The token stands in for a password and is valid for 15 minutes.
    os.environ["DBT_HOST"] = os.environ["DB_HOST"]
    os.environ["DBT_USER"] = os.environ["DB_USER"]
    os.environ["DBT_PASSWORD"] = token_from_env()

    _use_thread_locks()
    from dbt.cli.main import dbtRunner

    result = dbtRunner().invoke(
        [
            *command,
            "--target",
            "prod",
            "--project-dir",
            PROJECT_DIR,
            "--profiles-dir",
            PROJECT_DIR,
        ]
    )
    if result.exception is not None:
        raise result.exception

    counts: dict[str, int] = {}
    for node in getattr(result.result, "results", []):
        counts[node.status] = counts.get(node.status, 0) + 1
    summary = {"command": command, "success": result.success, "counts": counts}
    log.info("dbt %s: %s", " ".join(command), summary)

    # Raise so a failed model or test shows up as a Lambda error, not a quiet 200
    if not result.success:
        raise RuntimeError(f"dbt {' '.join(command)} failed: {counts}")
    return summary
