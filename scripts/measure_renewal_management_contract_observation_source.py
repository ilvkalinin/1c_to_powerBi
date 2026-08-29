#!/usr/bin/env python3
"""Measure progressive read-only plans for the reviewed observation parent extract."""

from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path
from typing import Any

import psycopg

from load_renewal_management_contract import config
from mart_connection import connect_with_retry


ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/renewal_management_contract_observation_extract.sql"


def subtract_months(end: date, months: int) -> date:
    month_index = end.year * 12 + end.month - 1 - months
    return date(month_index // 12, month_index % 12 + 1, 1)


def measure(end: date, months: list[int]) -> list[dict[str, Any]]:
    extract = EXTRACT.read_text(encoding="utf-8").strip().rstrip(";")
    query = (
        "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) "
        f"SELECT * FROM ({extract}) AS observed_state "
        "WHERE membership_end_date >= %s AND membership_end_date < %s"
    )
    connection = connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart")
    try:
        results: list[dict[str, Any]] = []
        with connection.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SELECT set_config('statement_timeout', '180000', true)")
            for month_count in months:
                start = subtract_months(end, month_count)
                cursor.execute(query, (start, end))
                document = cursor.fetchone()[0][0]
                plan = document["Plan"]
                results.append({
                    "start_date": start,
                    "end_date": end,
                    "months": month_count,
                    "rows": plan.get("Actual Rows"),
                    "execution_ms": document.get("Execution Time"),
                    "planning_ms": document.get("Planning Time"),
                    "node_type": plan.get("Node Type"),
                    "shared_hit_blocks": plan.get("Shared Hit Blocks"),
                    "shared_read_blocks": plan.get("Shared Read Blocks"),
                    "temp_read_blocks": plan.get("Temp Read Blocks"),
                    "temp_written_blocks": plan.get("Temp Written Blocks"),
                })
            cursor.execute("ROLLBACK")
        return results
    finally:
        connection.close()


def json_default(value: Any) -> Any:
    if isinstance(value, date):
        return value.isoformat()
    raise TypeError(type(value).__name__)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--end-date", type=date.fromisoformat, default=date(2026, 9, 1))
    parser.add_argument("--months", type=int, nargs="+", default=[1, 2, 3, 6])
    args = parser.parse_args()
    if any(month <= 0 for month in args.months):
        parser.error("all --months values must be positive")
    print(json.dumps({"query": "reviewed observation parent extract", "plans": measure(args.end_date, args.months)}, default=json_default, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
