#!/usr/bin/env python3
"""Synchronise room slots by exact source-snapshot row differences."""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_lesson_room_slot_5m import COLUMNS, br003_horizon, connect_with_retry, rendered, source_expected

TABLE = "mart.lesson_room_slot_5m"
STAGE = "_lesson_room_slot_5m_incremental_stage"
CONFIG = ROOT / "config/lesson_room_slot_5m_incremental.json"
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
    if any(payload.get(key) != value for key, value in expected.items()):
        raise RuntimeError("Unexpected incremental config")
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


def stage_controls(cursor) -> tuple[int, int, int, int, int]:
    cursor.execute(
        f"SELECT count(*)::bigint, "
        f"count(*) FILTER (WHERE source_kind='group_lesson')::bigint, "
        f"count(*) FILTER (WHERE source_kind='prebooking')::bigint, "
        f"count(DISTINCT source_lesson_id) FILTER (WHERE source_kind='group_lesson')::bigint, "
        f"count(DISTINCT source_lesson_id) FILTER (WHERE source_kind='prebooking')::bigint "
        f"FROM {STAGE}"
    )
    return cursor.fetchone()


def run_refresh(start, end) -> None:
    begun = time.monotonic()
    extract = rendered(ROOT / "sql/marts/lesson_room_slot_5m_extract.sql", start, end)
    controls = rendered(ROOT / "sql/marts/lesson_room_slot_5m_source_controls.sql", start, end)
    with tempfile.TemporaryDirectory(prefix="lesson_room_slot_incremental_") as temporary:
        transport = Path(temporary) / "source.copy"
        with connect_with_retry("SOURCE_") as source:
            with source.cursor() as cursor:
                cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                expected = source_expected(cursor, controls)
                with transport.open("wb") as output, cursor.copy(
                    f"COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)"
                ) as copied:
                    for block in copied:
                        output.write(block)
                rows = cursor.rowcount
            source.rollback()
        if rows != expected[0]:
            raise RuntimeError("Source COPY rows differ from source controls")
        with connect_with_retry("MART_") as target:
            try:
                with target.cursor() as cursor:
                    cursor.execute("BEGIN")
                    cursor.execute("SET LOCAL statement_timeout='600s'")
                    cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TABLE + ":incremental",))
                    cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                    if cursor.fetchone()[0] is None:
                        raise RuntimeError("Incremental refresh requires the existing target")
                    cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                    with transport.open("rb") as input_file, cursor.copy(
                        f"COPY {STAGE} ({', '.join(COLUMN_LIST)}) FROM STDIN WITH (FORMAT BINARY)"
                    ) as copied:
                        while block := input_file.read(1_048_576):
                            copied.write(block)
                    if cursor.rowcount != rows or stage_controls(cursor) != expected:
                        raise RuntimeError("Staged source controls differ from source snapshot")
                    delta_before = exact_delta(cursor)
                    if not delta_before:
                        target.commit()
                        print(f"NO_CHANGES source_rows={rows} elapsed_seconds={time.monotonic()-begun:.3f}")
                        return
                    cursor.execute(
                        f"DELETE FROM {TABLE} AS target WHERE NOT EXISTS "
                        f"(SELECT 1 FROM {STAGE} AS stage WHERE {row_equal('target', 'stage')})"
                    )
                    deleted = cursor.rowcount
                    cursor.execute(
                        f"INSERT INTO {TABLE} ({', '.join(COLUMN_LIST)}) "
                        f"SELECT {', '.join('stage.' + column for column in COLUMN_LIST)} FROM {STAGE} AS stage "
                        f"WHERE NOT EXISTS (SELECT 1 FROM {TABLE} AS target WHERE {row_equal('target', 'stage')})"
                    )
                    inserted = cursor.rowcount
                    if exact_delta(cursor):
                        raise RuntimeError("Pre-commit exact source/target mismatch")
                    target.commit()
                    print(f"TARGET_COMMIT delta_before={delta_before} deleted={deleted} inserted={inserted} elapsed_seconds={time.monotonic()-begun:.3f}")
            except Exception:
                target.rollback()
                raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=CONFIG)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--plan-only", action="store_true")
    action.add_argument("--run", action="store_true")
    args = parser.parse_args()
    load_config(args.config)
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    if args.plan_only:
        print(f"PLAN_OK mode=target_row_diff horizon={start}..{end}")
        return
    run_refresh(start, end)


if __name__ == "__main__":
    main()
