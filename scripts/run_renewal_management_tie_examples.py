#!/usr/bin/env python3
"""Print PII-free source examples for the two renewal-management ties."""

from __future__ import annotations

import json
import sys
import time
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.load_children_package_sale import config
from scripts.mart_connection import connect_with_retry

QUERIES = (
    ("next_contract", ROOT / "docs/source_metadata/validation_sql/renewal_management_next_tie_examples_2026-08-29.sql"),
    ("latest_interaction", ROOT / "docs/source_metadata/validation_sql/renewal_management_interaction_tie_examples_2026-08-29.sql"),
)


def safe(value: object) -> object:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    return value


def main() -> None:
    output = {}
    for name, query in QUERIES:
        source = connect_with_retry(
            lambda: psycopg.connect(**(config("SOURCE_") | {"application_name": f"renewal_management_examples_{name}"})),
            endpoint="source",
        )
        try:
            with source.cursor() as cursor:
                cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                cursor.execute("SET LOCAL statement_timeout = '120s'")
                started = time.monotonic()
                cursor.execute(query.read_text(encoding="utf-8"))
                names = [column.name for column in cursor.description]
                rows = [{field: safe(value) for field, value in zip(names, row, strict=True)} for row in cursor.fetchall()]
                cursor.execute("ROLLBACK")
            output[name] = {"elapsed_seconds": round(time.monotonic() - started, 3), "rows": rows}
        finally:
            source.close()
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
