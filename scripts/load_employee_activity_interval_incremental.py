#!/usr/bin/env python3
"""Synchronise mart.employee_activity_interval by source-snapshot row diff.

The legacy employee_activity_interval runner remains the separate full rebuild.
This runner reuses only the reviewed source projection and controls; it never
calls that runner's full-table DELETE + INSERT path.
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

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_children_package_sale import br003_horizon
from scripts.load_employee_activity_interval import (
    COLUMNS,
    TABLE,
    branch_query,
    close,
    expected,
    open_source,
    open_target,
    reconcile,
    render,
    source_copy,
    transport_batches,
)


DEFAULT_CONFIG = ROOT / "config/employee_activity_interval_incremental.json"
STAGE = "_employee_activity_interval_incremental_stage"
COLUMN_LIST = tuple(column.strip() for column in COLUMNS.split(","))


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected_values = {
        "object": TABLE,
        "mode": "target_row_diff",
        "timezone": "Europe/Moscow",
        "change_detection": "source_snapshot_to_target_exact_row_diff",
        "deletion_policy": "delete_target_rows_absent_or_different_in_source_snapshot",
        "no_change_policy": "no_final_target_dml",
    }
    for key, value in expected_values.items():
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
    names = ", ".join(COLUMN_LIST)
    cursor.execute(
        f"SELECT count(*) FROM ("
        f"(SELECT {names} FROM {STAGE} EXCEPT ALL SELECT {names} FROM {TABLE}) "
        f"UNION ALL "
        f"(SELECT {names} FROM {TABLE} EXCEPT ALL SELECT {names} FROM {STAGE})"
        f") AS delta"
    )
    return cursor.fetchone()[0]


def validate_stage(cursor, expected_rows: int, expected_keys: int) -> None:
    cursor.execute(
        f"SELECT count(*)::bigint, count(DISTINCT activity_event_key)::bigint, "
        f"count(*) FILTER (WHERE activity_event_key IS NULL OR activity_date IS NULL "
        f"OR club_id IS NULL OR employee_id IS NULL OR start_at IS NULL OR end_at IS NULL "
        f"OR end_at <= start_at OR duration_minutes < 0 "
        f"OR activity_kind NOT IN ('TRAINING','DUTY','COUPON_1','COUPON_2') "
        f"OR payment_kind NOT IN ('Платно','Бесплатно','Дежурство'))::bigint "
        f"FROM {STAGE}"
    )
    rows, keys, invalid = cursor.fetchone()
    if (rows, keys, invalid) != (expected_rows, expected_keys, 0):
        raise RuntimeError(f"Invalid staged activity snapshot rows={rows} keys={keys} invalid={invalid}")


def export_source_snapshot(start: date, end: date, directory: Path):
    owner = open_source("employee_activity_interval_incremental_snapshot_owner")
    try:
        with owner.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout = '600s'")
            cursor.execute("SELECT pg_export_snapshot()")
            snapshot_id = cursor.fetchone()[0]
        source_expected = expected(snapshot_id, start, end)
        extract = render(ROOT / "sql/marts/employee_activity_interval_extract.sql", start, end)
        manifest = []
        for ordinal, (label, kind_filter, batch_start, batch_end) in enumerate(transport_batches(start, end), start=1):
            transfer = directory / f"{ordinal:02d}.copy"
            rows = source_copy(snapshot_id, branch_query(extract, kind_filter, batch_start, batch_end), transfer, label)
            manifest.append((label, transfer, rows))
        return source_expected, manifest
    finally:
        close(owner)


def run_refresh(start: date, end: date) -> None:
    begun = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="employee_activity_interval_incremental_") as temporary:
        source_expected, manifest = export_source_snapshot(start, end, Path(temporary))
        target = open_target("employee_activity_interval_incremental_target")
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SET LOCAL lock_timeout = '300s'")
                cursor.execute("SET LOCAL statement_timeout = '600s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.employee_activity_interval:incremental",))
                cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                if cursor.fetchone()[0] is None:
                    raise RuntimeError("Incremental refresh requires the existing target")
                cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                copied_total = 0
                for label, path, source_rows in manifest:
                    with cursor.copy(f"COPY {STAGE} ({', '.join(COLUMN_LIST)}) FROM STDIN WITH (FORMAT BINARY)") as copied, path.open("rb") as input_file:
                        while block := input_file.read(1_048_576):
                            copied.write(block)
                    if source_rows is not None and cursor.rowcount != source_rows:
                        raise RuntimeError(f"Stage COPY row mismatch for {label}")
                    copied_total += cursor.rowcount
                validate_stage(cursor, source_expected["rows"], source_expected["distinct_keys"])
                if copied_total != source_expected["rows"]:
                    raise RuntimeError("Source COPY total differs from source controls")
                delta_before = exact_delta(cursor)
                if not delta_before:
                    target.commit()
                    print(f"NO_CHANGES source_rows={copied_total} elapsed_seconds={time.monotonic() - begun:.3f}", flush=True)
                    return
                cursor.execute(
                    f"DELETE FROM {TABLE} AS target "
                    f"WHERE NOT EXISTS (SELECT 1 FROM {STAGE} AS stage WHERE {row_equal('target', 'stage')})"
                )
                deleted = cursor.rowcount
                cursor.execute(
                    f"INSERT INTO {TABLE} ({', '.join(COLUMN_LIST)}) "
                    f"SELECT {', '.join('stage.' + name for name in COLUMN_LIST)} FROM {STAGE} AS stage "
                    f"WHERE NOT EXISTS (SELECT 1 FROM {TABLE} AS target WHERE {row_equal('target', 'stage')})"
                )
                inserted = cursor.rowcount
                if exact_delta(cursor):
                    raise RuntimeError("Pre-commit exact source/target mismatch")
                reconcile(cursor, source_expected, start, end)
                target.commit()
                print(
                    f"TARGET_COMMIT source_rows={copied_total} delta_before={delta_before} "
                    f"deleted={deleted} inserted={inserted} elapsed_seconds={time.monotonic() - begun:.3f}",
                    flush=True,
                )
        except Exception:
            close(target)
            raise
        finally:
            close(target)


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
        print(f"PLAN_OK mode=target_row_diff horizon={start}..{end}", flush=True)
        return
    run_refresh(start, end)


if __name__ == "__main__":
    main()
