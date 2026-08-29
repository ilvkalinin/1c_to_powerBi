#!/usr/bin/env python3
"""Run RM-ASOF-S2-001 controls in isolated read-only repeatable-read sessions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import psycopg

from load_renewal_management_contract import config
from mart_connection import connect_with_retry


ROOT = Path(__file__).resolve().parents[1]
SQL_FILES = {
    "source": ROOT / "docs/source_metadata/validation_sql/renewal_management_as_of_snapshot_stage2_source_2026-08-29.sql",
    "target": ROOT / "docs/source_metadata/validation_sql/renewal_management_as_of_snapshot_stage2_target_2026-08-29.sql",
}


def json_default(value: Any) -> Any:
    if isinstance(value, (date, datetime, Decimal)):
        return str(value)
    raise TypeError(f"Unsupported value in validation result: {type(value)!r}")


def statements(path: Path) -> list[str]:
    """Split this deliberately semicolon-free control file into SELECT statements."""
    body = path.read_text(encoding="utf-8")
    sql_only = "\n".join(line for line in body.splitlines() if not line.lstrip().startswith("--"))
    return [statement.strip() for statement in sql_only.split(";") if statement.strip()]


def control_id(statement: str) -> str:
    match = re.search(r"'((?:ASOF)-V[0-9]+(?:-META)?)'::text\s+AS\s+control_id", statement, flags=re.IGNORECASE)
    if not match:
        raise ValueError("Every Stage 2 statement must expose a literal control_id")
    return match.group(1).upper()


def run_endpoint(endpoint: str, statement_timeout_ms: int) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for statement in statements(SQL_FILES[endpoint]):
        identifier = control_id(statement)
        connection = connect_with_retry(
            lambda: psycopg.connect(**config("SOURCE_" if endpoint == "source" else "MART_")),
            endpoint="source" if endpoint == "source" else "mart",
        )
        try:
            with connection.cursor() as cursor:
                cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                cursor.execute("SELECT set_config('statement_timeout', %s, true)", (str(statement_timeout_ms),))
                cursor.execute(statement)
                columns = [description.name for description in cursor.description]
                rows = [dict(zip(columns, row, strict=True)) for row in cursor.fetchall()]
                results.append({"control_id": identifier, "rows": rows})
                cursor.execute("ROLLBACK")
        finally:
            connection.close()
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", choices=("source", "target", "all"), default="all")
    parser.add_argument("--source-timeout-ms", type=int, default=300_000)
    parser.add_argument("--target-timeout-ms", type=int, default=60_000)
    args = parser.parse_args()

    endpoints = ("source", "target") if args.endpoint == "all" else (args.endpoint,)
    payload: dict[str, Any] = {
        "package": "RM-ASOF-S2-001",
        "isolation": "REPEATABLE READ, READ ONLY",
        "results": {},
    }
    for endpoint in endpoints:
        timeout_ms = args.source_timeout_ms if endpoint == "source" else args.target_timeout_ms
        payload["results"][endpoint] = run_endpoint(endpoint, timeout_ms)
    print(json.dumps(payload, ensure_ascii=False, default=json_default, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # exact error is needed for a non-mutating Stage 2 record
        print(json.dumps({"package": "RM-ASOF-S2-001", "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise
