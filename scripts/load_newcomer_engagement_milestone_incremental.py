#!/usr/bin/env python3
"""Synchronise newcomer engagement milestones without invoking full rebuild."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_newcomer_engagement_milestone import (
    COLUMNS,
    TARGET,
    br003_horizon,
    config,
    copy_source,
)
from scripts.mart_connection import connect_with_retry

CONFIG = ROOT / "config/newcomer_engagement_milestone_incremental.json"
STAGE = "_newcomer_engagement_milestone_incremental_stage"
COLUMN_NAMES = tuple(column.strip() for column in COLUMNS.split(","))
SELECTED = ", ".join(COLUMN_NAMES)
STAGE_SELECTED = ", ".join(f"stage.{column}" for column in COLUMN_NAMES)
EQUALITY = " AND ".join(
    f"target.{column} IS NOT DISTINCT FROM stage.{column}" for column in COLUMN_NAMES
)


def load_config(path: Path) -> None:
    actual = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "objects": [TARGET],
        "mode": "target_row_diff",
        "timezone": "Europe/Moscow",
        "change_detection": "source_snapshot_to_target_exact_row_multiset_diff",
        "deletion_policy": "delete_target_rows_absent_or_different_in_source_snapshot",
        "no_change_policy": "no_final_target_dml",
    }
    if any(actual.get(key) != value for key, value in expected.items()):
        raise RuntimeError("Unexpected newcomer milestone incremental configuration")
    if actual.get("watermark") is not None or actual.get("incremental_sla") is not None:
        raise RuntimeError("Newcomer milestone runner must not claim watermark or SLA")


def exact_delta(cursor) -> int:
    cursor.execute(
        f"""SELECT count(*) FROM (
          (SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET})
          UNION ALL
          (SELECT {SELECTED} FROM {TARGET} EXCEPT ALL SELECT {SELECTED} FROM {STAGE})
        ) AS exact_difference"""
    )
    return cursor.fetchone()[0]


def require_controls(cursor, expected_rows: int) -> None:
    cursor.execute(
        f"""SELECT count(*)::bigint,
                   count(DISTINCT (contract_id, client_id, checkpoint_day))::bigint,
                   count(*) FILTER (WHERE checkpoint_date <> membership_start_date + checkpoint_day - 1)::bigint,
                   count(*) FILTER (WHERE visit_count_to_checkpoint < 0)::bigint
            FROM {TARGET}"""
    )
    if cursor.fetchone() != (expected_rows, expected_rows, 0, 0):
        raise RuntimeError("Persisted newcomer milestone controls failed")


def run(start, end) -> None:
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="newcomer_engagement_milestone_incremental_") as directory:
        path = Path(directory) / "source.copy"
        expected_rows = copy_source(start, end, path)
        with connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
            try:
                with target.cursor() as cursor:
                    cursor.execute("BEGIN")
                    cursor.execute("SELECT to_regclass(%s)", (TARGET,))
                    if cursor.fetchone()[0] is None:
                        raise RuntimeError("Incremental refresh requires existing target")
                    cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET + ":incremental",))
                    cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP")
                    with path.open("rb") as source, cursor.copy(
                        f"COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
                    ) as copy:
                        while block := source.read(1_048_576):
                            copy.write(block)
                    cursor.execute(
                        f"""SELECT count(*)::bigint,
                                   count(DISTINCT (contract_id, client_id, checkpoint_day))::bigint,
                                   count(*) FILTER (WHERE checkpoint_date <> membership_start_date + checkpoint_day - 1)::bigint,
                                   count(*) FILTER (WHERE visit_count_to_checkpoint < 0)::bigint
                            FROM {STAGE}"""
                    )
                    if cursor.fetchone() != (expected_rows, expected_rows, 0, 0):
                        raise RuntimeError("Staged newcomer milestone controls failed")
                    before = exact_delta(cursor)
                    if not before:
                        target.commit()
                        print(f"NO_CHANGES elapsed_seconds={time.monotonic() - started:.3f}", flush=True)
                        return
                    cursor.execute(
                        f"DELETE FROM {TARGET} AS target WHERE NOT EXISTS "
                        f"(SELECT 1 FROM {STAGE} AS stage WHERE {EQUALITY})"
                    )
                    cursor.execute(
                        f"INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} AS stage "
                        f"WHERE NOT EXISTS (SELECT 1 FROM {TARGET} AS target WHERE {EQUALITY})"
                    )
                    if exact_delta(cursor):
                        raise RuntimeError("Pre-commit exact mismatch")
                    require_controls(cursor, expected_rows)
                    target.commit()
                    print(f"TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic() - started:.3f}", flush=True)
            except Exception:
                target.rollback()
                raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=CONFIG)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan-only", action="store_true")
    mode.add_argument("--run", action="store_true", help="perform approved target DML")
    args = parser.parse_args()
    load_config(args.config)
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    if args.plan_only:
        print(f"PLAN_OK mode=target_row_diff horizon={start}..{end}", flush=True)
        return
    run(start, end)


if __name__ == "__main__":
    main()
