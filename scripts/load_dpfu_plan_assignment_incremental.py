#!/usr/bin/env python3
"""Refresh source-different rows of mart.dpfu_plan_assignment only.

The existing load_dpfu_plan_assignment.py remains the separate approved full
rebuild.  This runner uses the same reviewed projection but does not invoke
that loader or its DELETE + COPY path.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_dpfu_plan_assignment import (
    COLUMNS,
    br003_horizon,
    config,
    extract_sql,
    require_client_code_quality,
    require_stage_integrity,
    source_controls,
    target_controls,
)
from scripts.mart_connection import connect_with_retry


DEFAULT_CONFIG = ROOT / "config/dpfu_plan_assignment_incremental.json"
TABLE = "mart.dpfu_plan_assignment"
STAGE = "_dpfu_plan_assignment_incremental_stage"
COLUMN_LIST = tuple(column.strip() for column in COLUMNS.split(","))


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "object": TABLE,
        "mode": "target_row_diff",
        "timezone": "Europe/Moscow",
        "change_detection": "source_snapshot_to_target_exact_row_diff",
        "deletion_policy": "delete_target_rows_absent_or_different_in_source_snapshot",
        "no_change_policy": "no_final_target_dml",
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise RuntimeError(f"Unexpected incremental config {key}")
    if payload.get("watermark") is not None or payload.get("incremental_sla") is not None:
        raise RuntimeError("Unvalidated watermark or SLA is forbidden")


def row_equal(left: str, right: str) -> str:
    return " AND ".join(
        f"{left}.{column} IS NOT DISTINCT FROM {right}.{column}"
        for column in COLUMN_LIST
    )


def exact_delta(cursor) -> int:
    columns = ", ".join(COLUMN_LIST)
    cursor.execute(
        f"SELECT count(*) FROM ("
        f"(SELECT {columns} FROM {STAGE} EXCEPT ALL SELECT {columns} FROM {TABLE}) "
        f"UNION ALL "
        f"(SELECT {columns} FROM {TABLE} EXCEPT ALL SELECT {columns} FROM {STAGE})"
        f") AS delta"
    )
    return cursor.fetchone()[0]


def run_refresh(start: date, end: date) -> None:
    begun = time.monotonic()
    query = extract_sql(start, end)
    with tempfile.TemporaryDirectory(prefix="dpfu_plan_assignment_incremental_") as temporary:
        transfer = Path(temporary) / "source.copy"
        with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source:
            with source.cursor() as source_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                source_cursor.execute("SET LOCAL statement_timeout = '300000'")
                require_client_code_quality(source_cursor, query)
                expected = source_controls(source_cursor, query)
                with transfer.open("wb") as output, source_cursor.copy(
                    f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)"
                ) as copied:
                    for block in copied:
                        output.write(block)
                source_rows = source_cursor.rowcount
            source.rollback()
        if source_rows != expected[0]:
            raise RuntimeError("Source COPY row count differs from source controls")
        with connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
            try:
                with target.cursor() as cursor:
                    cursor.execute("BEGIN")
                    cursor.execute("SET LOCAL statement_timeout = '300000'")
                    cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.dpfu_plan_assignment:incremental",))
                    cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                    if cursor.fetchone()[0] is None:
                        raise RuntimeError("Incremental refresh requires the existing target")
                    cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                    with cursor.copy(f"COPY {STAGE} ({', '.join(COLUMN_LIST)}) FROM STDIN WITH (FORMAT BINARY)") as copied, transfer.open("rb") as input_file:
                        while block := input_file.read(1_048_576):
                            copied.write(block)
                    if cursor.rowcount != source_rows:
                        raise RuntimeError("Stage COPY row count differs from source COPY")
                    # Reuse the existing source-stage contract, with its table
                    # name substituted only inside this local target transaction.
                    cursor.execute(f"ALTER TABLE {STAGE} RENAME TO _dpfu_plan_assignment_stage")
                    require_stage_integrity(cursor)
                    if target_controls(cursor, "_dpfu_plan_assignment_stage") != expected:
                        raise RuntimeError("Staged source controls differ from source snapshot")
                    cursor.execute("ALTER TABLE _dpfu_plan_assignment_stage RENAME TO " + STAGE)
                    delta_before = exact_delta(cursor)
                    if not delta_before:
                        target.commit()
                        print(f"NO_CHANGES source_rows={source_rows} elapsed_seconds={time.monotonic() - begun:.3f}", flush=True)
                        return
                    cursor.execute(
                        f"DELETE FROM {TABLE} AS target "
                        f"WHERE NOT EXISTS (SELECT 1 FROM {STAGE} AS stage WHERE {row_equal('target', 'stage')})"
                    )
                    deleted = cursor.rowcount
                    cursor.execute(
                        f"INSERT INTO {TABLE} ({', '.join(COLUMN_LIST)}) "
                        f"SELECT {', '.join('stage.' + column for column in COLUMN_LIST)} FROM {STAGE} AS stage "
                        f"WHERE NOT EXISTS (SELECT 1 FROM {TABLE} AS target WHERE {row_equal('target', 'stage')})"
                    )
                    inserted = cursor.rowcount
                    delta_after = exact_delta(cursor)
                    if delta_after:
                        raise RuntimeError(f"Pre-commit exact source/target mismatch: {delta_after}")
                    target.commit()
                    print(
                        f"TARGET_COMMIT source_rows={source_rows} delta_before={delta_before} "
                        f"deleted={deleted} inserted={inserted} elapsed_seconds={time.monotonic() - begun:.3f}",
                        flush=True,
                    )
            except Exception:
                target.rollback()
                raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan-only", action="store_true")
    mode.add_argument("--run", action="store_true")
    parser.add_argument("--start", type=date.fromisoformat)
    parser.add_argument("--end", type=date.fromisoformat)
    args = parser.parse_args()
    load_config(args.config)
    default_start, default_end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    start, end = args.start or default_start, args.end or default_end
    if start >= end:
        raise SystemExit("--start must be earlier than --end")
    if args.plan_only:
        if not extract_sql(start, end).startswith("SELECT r._fld6613::date"):
            raise RuntimeError("Unexpected reviewed source extract")
        print(f"PLAN_OK mode=target_row_diff horizon={start}..{end}", flush=True)
        return
    run_refresh(start, end)


if __name__ == "__main__":
    main()
