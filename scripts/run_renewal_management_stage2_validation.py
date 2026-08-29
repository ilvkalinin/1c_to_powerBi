#!/usr/bin/env python3
"""Run full-population source-only controls for renewal management."""

from __future__ import annotations

import json
import argparse
import sys
import time
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.load_children_package_sale import config
from scripts.mart_connection import connect_with_retry


CONTROL_SQL = ROOT / "docs/source_metadata/validation_sql/renewal_management_stage2_full_2026-08-29.sql"
TIMEOUT_SECONDS = 300


def statements() -> list[str]:
    body = "\n".join(
        line for line in CONTROL_SQL.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("--")
    )
    return [statement.strip() for statement in body.split(";") if statement.strip()]


def json_value(value: object) -> object:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    return str(value) if not isinstance(value, (str, int, float, bool, type(None))) else value


def run(control_number: int | None) -> None:
    output: list[dict[str, object]] = []
    for ordinal, statement in enumerate(statements(), start=1):
        if control_number is not None and ordinal != control_number:
            continue
        source = connect_with_retry(
            lambda: psycopg.connect(**(config("SOURCE_") | {"application_name": f"renewal_management_stage2_{ordinal}"})),
            endpoint="source",
        )
        try:
            with source.cursor() as cursor:
                cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                cursor.execute(f"SET LOCAL statement_timeout = '{TIMEOUT_SECONDS}s'")
                started = datetime.now(timezone.utc)
                timer = time.monotonic()
                cursor.execute(statement)
                columns = [column.name for column in cursor.description]
                rows = [
                    {name: json_value(value) for name, value in zip(columns, row, strict=True)}
                    for row in cursor.fetchall()
                ]
                cursor.execute("ROLLBACK")
                output.append({
                    "control_id": rows[0].get("control_id") if rows else "NO_ROWS",
                    "executed_at_utc": started.isoformat(),
                    "elapsed_seconds": round(time.monotonic() - timer, 3),
                    "rows": rows,
                })
        finally:
            source.close()
    print(json.dumps({"source_sessions": "fresh repeatable_read_read_only per control", "controls": output}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--control-number", type=int)
    arguments = parser.parse_args()
    run(arguments.control_number)
