#!/usr/bin/env python3
"""Synchronise CRM compact facts by exact source-snapshot row differences.

This is intentionally independent from ``load_crm_br032.py``.  The legacy
loader remains the explicitly invoked full rebuild.  This runner uses its
reviewed source projection, but stages it first and changes final mart rows
only where the source snapshot differs.  It does not create or alter schema
objects.
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

from scripts.load_crm_br032 import (
    COLUMNS,
    TARGETS,
    assert_core_created_window,
    br003_horizon,
    connect_with_retry,
    next_chunk,
    render,
    source_copy_to_file,
    sql_sections,
)


DEFAULT_CONFIG = ROOT / "config/crm_br032_incremental.json"
STAGES = {
    "core": "_crm_incremental_core",
    "phone": "_crm_incremental_phone",
    "feedback": "_crm_incremental_feedback",
    "club_day": "_crm_incremental_club_day",
}
ORDER = ("core", "phone", "feedback", "club_day")
SOURCE_CHUNKED = ("core", "phone", "feedback")


def columns(name: str) -> tuple[str, ...]:
    return tuple(part.strip() for part in COLUMNS[name].split(","))


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "objects": [TARGETS[name] for name in ORDER],
        "mode": "composite_target_row_diff",
        "timezone": "Europe/Moscow",
        "change_detection": "source_snapshot_to_target_exact_row_multiset_diff",
        "deletion_policy": "delete_target_rows_absent_or_different_in_source_snapshot",
        "no_change_policy": "no_final_target_dml",
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise RuntimeError(f"Unexpected incremental config {key}")
    if payload.get("watermark") is not None or payload.get("incremental_sla") is not None:
        raise RuntimeError("Unvalidated watermark or SLA is forbidden")


def qualified_columns(alias: str, name: str) -> str:
    return ", ".join(f"{alias}.{column}" for column in columns(name))


def row_equal(left: str, right: str, name: str) -> str:
    return " AND ".join(
        f"{left}.{column} IS NOT DISTINCT FROM {right}.{column}"
        for column in columns(name)
    )


def copy_source_snapshot(start: date, end: date, chunk_months: int, directory: Path) -> list[tuple[str, Path, int]]:
    """Export the four reviewed facts from one read-only source snapshot."""
    sections = sql_sections()
    manifest: list[tuple[str, Path, int]] = []
    ordinal = 0
    source = connect_with_retry("SOURCE_", "crm_br032_incremental_source")
    try:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout = '300000'")
            assert_core_created_window(cursor, start, end)
            for name in SOURCE_CHUNKED:
                chunk_start = start
                while chunk_start < end:
                    chunk_end = next_chunk(chunk_start, end, chunk_months)
                    query = render(sections[name], start, end, chunk_start, chunk_end)
                    path, row_count = source_copy_to_file(cursor, name, query, directory, ordinal)
                    manifest.append((name, path, row_count))
                    ordinal += 1
                    chunk_start = chunk_end
            chunk_start = start
            while chunk_start < end:
                chunk_end = next_chunk(chunk_start, end, chunk_months)
                query = render(sections["club_day"], chunk_start, chunk_end)
                path, row_count = source_copy_to_file(cursor, "club_day", query, directory, ordinal)
                manifest.append(("club_day", path, row_count))
                ordinal += 1
                chunk_start = chunk_end
        source.rollback()
    except Exception:
        source.rollback()
        raise
    finally:
        source.close()
    return manifest


def create_stages(cursor) -> None:
    for name in ORDER:
        cursor.execute(
            f"CREATE TEMP TABLE {STAGES[name]} "
            f"(LIKE {TARGETS[name]} INCLUDING DEFAULTS) ON COMMIT DROP"
        )


def copy_stage(cursor, name: str, path: Path, expected_rows: int) -> None:
    column_list = ", ".join(columns(name))
    with cursor.copy(
        f"COPY {STAGES[name]} ({column_list}) FROM STDIN WITH (FORMAT BINARY)"
    ) as copied, path.open("rb") as source_file:
        while block := source_file.read(1_048_576):
            copied.write(block)
    if cursor.rowcount != expected_rows:
        raise RuntimeError(f"Stage COPY row count mismatch for {name}")


def scalar(cursor, statement: str) -> int:
    cursor.execute(statement)
    return cursor.fetchone()[0]


def validate_stages(cursor) -> None:
    unique_keys = {
        "core": "interaction_id",
        "phone": "interaction_id, phone_reference_id, phone_event_id",
        "club_day": "event_date, club_id",
    }
    for name, key_columns in unique_keys.items():
        duplicates = scalar(cursor, f"SELECT count(*) FROM (SELECT {key_columns} FROM {STAGES[name]} GROUP BY {key_columns} HAVING count(*) > 1) AS duplicate_key")
        if duplicates:
            raise RuntimeError(f"Source snapshot has duplicate {name} keys: {duplicates}")
    feedback_columns = ", ".join(columns("feedback"))
    duplicates = scalar(cursor, f"SELECT count(*) FROM (SELECT {feedback_columns} FROM {STAGES['feedback']} GROUP BY {feedback_columns} HAVING count(*) > 1) AS duplicate_full_row")
    if duplicates:
        raise RuntimeError(f"Source snapshot has duplicate feedback full rows: {duplicates}")
    invalid_core = scalar(cursor, f"SELECT count(*) FROM {STAGES['core']} WHERE interaction_id IS NULL OR task_id IS NULL OR created_at IS NULL OR NOT (sales_scope OR guest_scope)")
    invalid_feedback = scalar(cursor, f"SELECT count(*) FROM {STAGES['feedback']} WHERE worked_flag <> (worked_at IS NOT NULL) OR (response_minutes IS NOT NULL AND worked_at IS NULL)")
    orphan_phone = scalar(cursor, f"SELECT count(*) FROM {STAGES['phone']} p WHERE NOT EXISTS (SELECT 1 FROM {STAGES['core']} c WHERE c.interaction_id = p.interaction_id)")
    if invalid_core or invalid_feedback or orphan_phone:
        raise RuntimeError(f"Invalid staged source rows core={invalid_core} feedback={invalid_feedback} orphan_phone={orphan_phone}")


def delete_different_rows(cursor, name: str) -> int:
    target, stage = TARGETS[name], STAGES[name]
    cursor.execute(
        f"DELETE FROM {target} AS target "
        f"WHERE NOT EXISTS (SELECT 1 FROM {stage} AS stage WHERE {row_equal('target', 'stage', name)})"
    )
    return cursor.rowcount


def insert_missing_rows(cursor, name: str) -> int:
    target, stage = TARGETS[name], STAGES[name]
    column_list = ", ".join(columns(name))
    cursor.execute(
        f"INSERT INTO {target} ({column_list}) "
        f"SELECT {qualified_columns('stage', name)} FROM {stage} AS stage "
        f"WHERE NOT EXISTS (SELECT 1 FROM {target} AS target WHERE {row_equal('target', 'stage', name)})"
    )
    return cursor.rowcount


def assert_exact_target_match(cursor, name: str) -> None:
    column_list = ", ".join(columns(name))
    target, stage = TARGETS[name], STAGES[name]
    cursor.execute(
        f"SELECT count(*) FROM ("
        f"(SELECT {column_list} FROM {stage} EXCEPT ALL SELECT {column_list} FROM {target}) "
        f"UNION ALL "
        f"(SELECT {column_list} FROM {target} EXCEPT ALL SELECT {column_list} FROM {stage})"
        f") AS delta"
    )
    delta = cursor.fetchone()[0]
    if delta:
        raise RuntimeError(f"Pre-commit exact source/target mismatch for {name}: {delta}")


def run_refresh(start: date, end: date, chunk_months: int) -> None:
    begun = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="crm_br032_incremental_") as temporary:
        manifest = copy_source_snapshot(start, end, chunk_months, Path(temporary))
        expected = {name: sum(rows for fact, _path, rows in manifest if fact == name) for name in ORDER}
        target = connect_with_retry("MART_", "crm_br032_incremental_target")
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SET LOCAL statement_timeout = '300000'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.crm_br032:incremental",))
                for name in ORDER:
                    cursor.execute("SELECT to_regclass(%s)", (TARGETS[name],))
                    if cursor.fetchone()[0] is None:
                        raise RuntimeError(f"Incremental refresh requires existing target {TARGETS[name]}")
                create_stages(cursor)
                for name, path, row_count in manifest:
                    copy_stage(cursor, name, path, row_count)
                validate_stages(cursor)
                deleted = {name: delete_different_rows(cursor, name) for name in ("phone", "feedback", "core", "club_day")}
                inserted = {name: insert_missing_rows(cursor, name) for name in ("core", "phone", "feedback", "club_day")}
                for name in ORDER:
                    assert_exact_target_match(cursor, name)
                target.commit()
            print(
                "TARGET_COMMIT "
                f"source_rows={expected} deleted={deleted} inserted={inserted} "
                f"elapsed_seconds={time.monotonic() - begun:.3f}",
                flush=True,
            )
        except Exception:
            target.rollback()
            raise
        finally:
            target.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--plan-only", action="store_true", help="validate local runner inputs only")
    action.add_argument("--run", action="store_true", help="apply approved row-difference refresh")
    parser.add_argument("--start", type=date.fromisoformat)
    parser.add_argument("--end", type=date.fromisoformat)
    parser.add_argument("--chunk-months", type=int, default=3)
    args = parser.parse_args()
    load_config(args.config)
    if not 1 <= args.chunk_months <= 12:
        raise SystemExit("--chunk-months must be between 1 and 12")
    default_start, default_end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    start, end = args.start or default_start, args.end or default_end
    if start >= end:
        raise SystemExit("--start must be earlier than --end")
    if args.plan_only:
        if set(sql_sections()) != set(ORDER):
            raise RuntimeError("Unexpected reviewed CRM source sections")
        print(f"PLAN_OK mode=composite_target_row_diff horizon={start}..{end} chunk_months={args.chunk_months}", flush=True)
        return
    run_refresh(start, end, args.chunk_months)


if __name__ == "__main__":
    try:
        main()
    except psycopg.Error as error:
        print(f"CRM_INCREMENTAL_FAILED {type(error).__name__} sqlstate={error.sqlstate}", file=sys.stderr, flush=True)
        raise SystemExit(1)
