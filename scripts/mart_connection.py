"""Shared bounded connection retry policy for mart runners."""

from __future__ import annotations

import os
import time
from collections.abc import Callable
from pathlib import Path
from typing import TypeVar

import psycopg


CONNECTION_RETRY_POLICY = "initial_attempt_plus_five_operational_retries_v1"
MAX_RETRIES = 5
DEFAULT_DELAY_SECONDS = 5
T = TypeVar("T")


def load_project_env() -> None:
    """Make the repository's ignored .env authoritative for DB credentials.

    It deliberately does not print values or evaluate shell syntax.  Loading
    happens when any shared connection helper is imported, before its first
    database socket can be opened.
    """
    environment_file = Path(__file__).resolve().parents[1] / ".env"
    if not environment_file.is_file():
        raise RuntimeError(f"Required credential file is absent: {environment_file}")
    for raw_line in environment_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            raise RuntimeError("Invalid .env line without '='")
        name, value = line.split("=", 1)
        name = name.strip()
        if not name or not name.replace("_", "a").isalnum() or name[0].isdigit():
            raise RuntimeError("Invalid .env variable name")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        os.environ[name] = value


load_project_env()


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
