#!/usr/bin/env python3
"""Atomically replace only the late-change window for newcomer milestones.

The full-rebuild loader remains ``load_newcomer_engagement_milestone.py``.
This runner has no watermark claim: it rebuilds a bounded output-date window
and retains older BR-003 history unchanged.
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

from scripts.load_newcomer_engagement_milestone import COLUMNS, TARGET, br003_horizon, config, rendered_extract
from scripts.mart_connection import connect_with_retry

CONFIG = ROOT / "config/newcomer_engagement_milestone_incremental.json"
STAGE = "_newcomer_engagement_milestone_incremental_stage"
COLUMN_NAMES = tuple(column.strip() for column in COLUMNS.split(","))
SELECTED = ", ".join(COLUMN_NAMES)
STAGE_SELECTED = ", ".join(f"stage.{column}" for column in COLUMN_NAMES)


def subtract_months(month_start: date, months: int) -> date:
    absolute = month_start.year * 12 + month_start.month - 1 - months
    return date(absolute // 12, absolute % 12 + 1, 1)


def load_config(path: Path) -> int:
    actual = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "objects": [TARGET], "mode": "bounded_sliding_window", "timezone": "Europe/Moscow",
        "change_detection": "source_snapshot_inside_late_change_window",
        "deletion_policy": "atomic_replace_inside_window",
        "outside_window_policy": "preserve_inside_br003_horizon",
        "late_change_evidence": "ASSUMPTION",
        "no_change_policy": "window_replace_even_when_row_counts_match",
    }
    if any(actual.get(key) != value for key, value in expected.items()):
        raise RuntimeError("Unexpected newcomer milestone incremental configuration")
    months = int(actual.get("months_in_window", 0))
    if months != 2:
        raise RuntimeError("Newcomer milestone window must remain two months until reviewed again")
    if actual.get("watermark") is not None or actual.get("incremental_sla") is not None:
        raise RuntimeError("Newcomer milestone runner must not claim watermark or SLA")
    return months


def boundaries(as_of_date: date, months: int) -> tuple[date, date, date]:
    horizon_start, window_end = br003_horizon(as_of_date)
    current_month = date(as_of_date.year, as_of_date.month, 1)
    return horizon_start, max(horizon_start, subtract_months(current_month, months - 1)), window_end


def copy_source_window(start: date, end: date, path: Path) -> int:
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            # Measured only for this exact short-window extract; never a server default.
            cursor.execute("SET LOCAL work_mem = '512MB'")
            with path.open("wb") as output, cursor.copy(
                f"COPY ({rendered_extract(start, end)}) TO STDOUT WITH (FORMAT BINARY)"
            ) as copy:
                while block := copy.read():
                    output.write(block)
            rows = cursor.rowcount
            source.rollback()
    return rows


def require_controls(cursor, relation: str, expected_rows: int, start: date, end: date) -> None:
    cursor.execute(
        f"""SELECT count(*)::bigint,
                   count(DISTINCT (contract_id, client_id, checkpoint_day))::bigint,
                   count(*) FILTER (WHERE checkpoint_date <> membership_start_date + checkpoint_day - 1)::bigint,
                   count(*) FILTER (WHERE visit_count_to_checkpoint < 0)::bigint,
                   count(*) FILTER (WHERE checkpoint_date < %s OR checkpoint_date >= %s)::bigint
            FROM {relation}""", (start, end),
    )
    if cursor.fetchone() != (expected_rows, expected_rows, 0, 0, 0):
        raise RuntimeError(f"Window controls failed for {relation}")


def exact_window_difference(cursor, start: date, end: date) -> int:
    cursor.execute(
        f"""SELECT count(*) FROM (
              (SELECT {SELECTED} FROM {STAGE}
               EXCEPT ALL SELECT {SELECTED} FROM {TARGET}
               WHERE checkpoint_date >= %s AND checkpoint_date < %s)
              UNION ALL
              (SELECT {SELECTED} FROM {TARGET}
               WHERE checkpoint_date >= %s AND checkpoint_date < %s
               EXCEPT ALL SELECT {SELECTED} FROM {STAGE})
            ) AS exact_difference""", (start, end, start, end),
    )
    return cursor.fetchone()[0]


def run(window_start: date, window_end: date) -> None:
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="newcomer_engagement_milestone_incremental_") as directory:
        path = Path(directory) / "source.copy"
        expected_rows = copy_source_window(window_start, window_end, path)
        with connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
            try:
                with target.cursor() as cursor:
                    cursor.execute("BEGIN")
                    cursor.execute("SELECT to_regclass(%s)", (TARGET,))
                    if cursor.fetchone()[0] is None:
                        raise RuntimeError("Incremental refresh requires existing target")
                    cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET + ":incremental",))
                    cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP")
                    with path.open("rb") as source, cursor.copy(f"COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copy:
                        while block := source.read(1_048_576):
                            copy.write(block)
                    require_controls(cursor, STAGE, expected_rows, window_start, window_end)
                    cursor.execute(f"DELETE FROM {TARGET} WHERE checkpoint_date >= %s AND checkpoint_date < %s", (window_start, window_end))
                    cursor.execute(f"INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} AS stage")
                    if cursor.rowcount != expected_rows:
                        raise RuntimeError("Target insert differs from source window")
                    if exact_window_difference(cursor, window_start, window_end):
                        raise RuntimeError("Pre-commit exact window mismatch")
                    require_controls(cursor, f"(SELECT * FROM {TARGET} WHERE checkpoint_date >= DATE '{window_start}' AND checkpoint_date < DATE '{window_end}') AS persisted", expected_rows, window_start, window_end)
                    target.commit()
                    print(f"TARGET_COMMIT window={window_start}..{window_end} rows={expected_rows} elapsed_seconds={time.monotonic() - started:.3f}", flush=True)
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
    months = load_config(args.config)
    horizon_start, window_start, window_end = boundaries(datetime.now(ZoneInfo("Europe/Moscow")).date(), months)
    print(f"PLAN_OK mode=bounded_sliding_window horizon={horizon_start}..{window_end} window={window_start}..{window_end} late_change_evidence=ASSUMPTION", flush=True)
    if args.run:
        run(window_start, window_end)


if __name__ == "__main__":
    main()
