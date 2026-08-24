"""Shared bounded connection retry policy for mart runners."""

from __future__ import annotations

import time
from collections.abc import Callable
from typing import TypeVar

import psycopg


CONNECTION_RETRY_POLICY = "initial_attempt_plus_five_operational_retries_v1"
MAX_RETRIES = 5
DEFAULT_DELAY_SECONDS = 5
T = TypeVar("T")


def connect_with_retry(
    opener: Callable[[], T], *, endpoint: str, delay_seconds: int = DEFAULT_DELAY_SECONDS
) -> T:
    """Open a session once, then retry five transient admission failures.

    Authentication/role/database-selection SQLSTATE classes are stable and
    fail immediately. SQL and data errors occur after connection admission and
    are deliberately outside this helper.
    """
    last_error: psycopg.OperationalError | None = None
    for retry in range(MAX_RETRIES + 1):
        try:
            return opener()
        except psycopg.OperationalError as error:
            if error.sqlstate and error.sqlstate.startswith(("28", "3D")):
                raise
            last_error = error
            if retry == MAX_RETRIES:
                break
            print(
                f"CONNECTION_RETRY endpoint={endpoint} retry={retry + 1}/{MAX_RETRIES} "
                f"delay_seconds={delay_seconds}",
                flush=True,
            )
            time.sleep(delay_seconds)
    assert last_error is not None
    raise last_error
