#!/usr/bin/env python3
"""Synchronise mart.employee_presence_day by exact source-snapshot row diff."""
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
from scripts.load_employee_presence_day import COLUMNS, TARGET, control, copy_out, months, open_db, reconcile

DEFAULT_CONFIG = ROOT / "config/employee_presence_day_incremental.json"
STAGE = "_employee_presence_day_incremental_stage"
COLUMN_LIST = tuple(column.strip() for column in COLUMNS.split(","))


def close(connection) -> None:
    if connection is not None:
        try:
            connection.rollback()
        except Exception:
            pass
        connection.close()


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "object": TARGET, "mode": "target_row_diff", "timezone": "Europe/Moscow",
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
    return " AND ".join(f"{left}.{column} IS NOT DISTINCT FROM {right}.{column}" for column in COLUMN_LIST)


def exact_delta(cursor) -> int:
    names = ", ".join(COLUMN_LIST)
    cursor.execute(
        f"SELECT count(*) FROM ((SELECT {names} FROM {STAGE} EXCEPT ALL SELECT {names} FROM {TARGET}) "
        f"UNION ALL (SELECT {names} FROM {TARGET} EXCEPT ALL SELECT {names} FROM {STAGE})) AS delta"
    )
    return cursor.fetchone()[0]


def export_snapshot(start: date, end: date, directory: Path):
    owner = open_db("SOURCE_", "employee_presence_day_incremental_snapshot_owner")
    try:
        with owner.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout = '600s'")
            cursor.execute("SET LOCAL work_mem = '128MB'")
            cursor.execute("SELECT pg_export_snapshot()")
            snapshot = cursor.fetchone()[0]
            source_expected = control(cursor, start, end)
        files = []
        for ordinal, (batch_start, batch_end) in enumerate(months(start, end), 1):
            path = directory / f"{ordinal:02d}.copy"
            files.append((path, copy_out(snapshot, batch_start, batch_end, path)))
        return source_expected, files
    finally:
        close(owner)


def validate_stage(cursor, expected_rows: int) -> None:
    cursor.execute(
        f"SELECT count(*)::bigint, count(DISTINCT (presence_date, club_id, employee_id))::bigint, "
        f"count(*) FILTER (WHERE presence_date IS NULL OR club_id IS NULL OR employee_id IS NULL OR presence_minutes < 0)::bigint "
        f"FROM {STAGE}"
    )
    rows, keys, invalid = cursor.fetchone()
    if (rows, keys, invalid) != (expected_rows, expected_rows, 0):
        raise RuntimeError(f"Invalid staged source rows={rows} keys={keys} invalid={invalid}")


def run_refresh(start: date, end: date) -> None:
    begun = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="employee_presence_day_incremental_") as temporary:
        source_expected, files = export_snapshot(start, end, Path(temporary))
        if sum(rows for _path, rows in files) != int(source_expected["target_grain_rows"]):
            raise RuntimeError("Source COPY rows differ from independent source controls")
        target = open_db("MART_", "employee_presence_day_incremental_target")
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SET LOCAL statement_timeout = '600s'")
                cursor.execute("SET LOCAL lock_timeout = '300s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET + ":incremental",))
                cursor.execute("SELECT to_regclass(%s)", (TARGET,))
                if cursor.fetchone()[0] is None:
                    raise RuntimeError("Incremental refresh requires the existing target")
                cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP")
                copied = 0
                for path, expected_rows in files:
                    with cursor.copy(f"COPY {STAGE} ({', '.join(COLUMN_LIST)}) FROM STDIN WITH (FORMAT BINARY)") as copied_to_target, path.open("rb") as input_file:
                        while block := input_file.read(1_048_576):
                            copied_to_target.write(block)
                    if cursor.rowcount != expected_rows:
                        raise RuntimeError("Target stage COPY row mismatch")
                    copied += cursor.rowcount
                validate_stage(cursor, int(source_expected["target_grain_rows"]))
                delta_before = exact_delta(cursor)
                if not delta_before:
                    target.commit()
                    print(f"NO_CHANGES source_rows={copied} elapsed_seconds={time.monotonic() - begun:.3f}", flush=True)
                    return
                cursor.execute(f"DELETE FROM {TARGET} AS target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} AS stage WHERE {row_equal('target', 'stage')})")
                deleted = cursor.rowcount
                cursor.execute(
                    f"INSERT INTO {TARGET} ({', '.join(COLUMN_LIST)}) "
                    f"SELECT {', '.join('stage.' + name for name in COLUMN_LIST)} FROM {STAGE} AS stage "
                    f"WHERE NOT EXISTS (SELECT 1 FROM {TARGET} AS target WHERE {row_equal('target', 'stage')})"
                )
                inserted = cursor.rowcount
                if exact_delta(cursor):
                    raise RuntimeError("Pre-commit exact source/target mismatch")
                reconcile(cursor, source_expected, start, end)
                target.commit()
                print(f"TARGET_COMMIT source_rows={copied} delta_before={delta_before} deleted={deleted} inserted={inserted} elapsed_seconds={time.monotonic() - begun:.3f}", flush=True)
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
