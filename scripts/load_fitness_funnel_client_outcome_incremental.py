#!/usr/bin/env python3
"""Synchronise mart.fitness_funnel_client_outcome without invoking its full rebuild."""
from __future__ import annotations

import argparse, json, sys, tempfile, time
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_fitness_funnel_client_outcome import (
    COLUMNS, TABLE, close_after_failure, expected_total, prepare_source_pool,
    reconciliation_sql, require_stage_contract, target_connection,
)

DEFAULT_CONFIG = ROOT / "config/fitness_funnel_client_outcome_incremental.json"
STAGE = "_fitness_funnel_client_outcome_incremental_stage"
COLUMN_LIST = tuple(column.strip() for column in COLUMNS.split(","))


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = {"object": TABLE, "mode": "target_row_diff", "timezone": "Europe/Moscow",
                "change_detection": "source_snapshot_to_target_exact_row_diff",
                "deletion_policy": "delete_target_rows_absent_or_different_in_source_snapshot",
                "no_change_policy": "no_final_target_dml"}
    for key, value in expected.items():
        if payload.get(key) != value:
            raise RuntimeError(f"Unexpected incremental config {key}")
    if payload.get("watermark") is not None or payload.get("incremental_sla") is not None:
        raise RuntimeError("Unvalidated watermark or SLA is forbidden")


def row_equal(left: str, right: str) -> str:
    return " AND ".join(f"{left}.{column} IS NOT DISTINCT FROM {right}.{column}" for column in COLUMN_LIST)


def exact_delta(cursor) -> int:
    names = ", ".join(COLUMN_LIST)
    cursor.execute(f"SELECT count(*) FROM ((SELECT {names} FROM {STAGE} EXCEPT ALL SELECT {names} FROM {TABLE}) UNION ALL (SELECT {names} FROM {TABLE} EXCEPT ALL SELECT {names} FROM {STAGE})) AS delta")
    return cursor.fetchone()[0]


def run_refresh(start: date, end: date, cap: int) -> None:
    begun = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="fitness_funnel_outcome_incremental_") as temporary:
        batches = prepare_source_pool(start, end, Path(temporary), cap)
        expected = expected_total(batches)
        target = target_connection("fitness_funnel_outcome_incremental_target")
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SET LOCAL lock_timeout='60s'")
                cursor.execute("SET LOCAL statement_timeout='600s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TABLE + ":incremental",))
                cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                if cursor.fetchone()[0] is None:
                    raise RuntimeError("Incremental refresh requires the existing target")
                cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                for batch in batches:
                    with batch.path.open("rb") as input_file, cursor.copy(f"COPY {STAGE} ({', '.join(COLUMN_LIST)}) FROM STDIN (FORMAT BINARY)") as copied:
                        while block := input_file.read(1_048_576):
                            copied.write(block)
                    if cursor.rowcount != batch.rows:
                        raise RuntimeError("Target stage COPY differs from source batch")
                # The reviewed contract has a fixed historical stage name; use a
                # temporary rename solely to reuse its independent checks.
                cursor.execute(f"ALTER TABLE {STAGE} RENAME TO _fitness_funnel_client_outcome_stage")
                require_stage_contract(cursor, expected, start, end)
                cursor.execute("ALTER TABLE _fitness_funnel_client_outcome_stage RENAME TO " + STAGE)
                delta_before = exact_delta(cursor)
                if not delta_before:
                    target.commit(); print(f"NO_CHANGES source_rows={sum(expected.values())} elapsed_seconds={time.monotonic()-begun:.3f}", flush=True); return
                cursor.execute(f"DELETE FROM {TABLE} AS target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} AS stage WHERE {row_equal('target', 'stage')})")
                deleted = cursor.rowcount
                cursor.execute(f"INSERT INTO {TABLE} ({', '.join(COLUMN_LIST)}) SELECT {', '.join('stage.' + name for name in COLUMN_LIST)} FROM {STAGE} AS stage WHERE NOT EXISTS (SELECT 1 FROM {TABLE} AS target WHERE {row_equal('target', 'stage')})")
                inserted = cursor.rowcount
                if exact_delta(cursor):
                    raise RuntimeError("Pre-commit exact source/target mismatch")
                cursor.execute(reconciliation_sql(expected, start, end))
                if [row for row in cursor.fetchall() if row[3] != "PASS"]:
                    raise RuntimeError("Target reconciliation failed")
                target.commit()
                print(f"TARGET_COMMIT source_rows={sum(expected.values())} delta_before={delta_before} deleted={deleted} inserted={inserted} elapsed_seconds={time.monotonic()-begun:.3f}", flush=True)
        except Exception:
            close_after_failure(target); raise
        finally:
            close_after_failure(target)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan-only", action="store_true")
    mode.add_argument("--run", action="store_true")
    parser.add_argument("--start", type=date.fromisoformat, default=date(2024, 1, 1))
    parser.add_argument("--end", type=date.fromisoformat, default=datetime.now(ZoneInfo("Europe/Moscow")).date() + timedelta(days=1))
    parser.add_argument("--max-derived-bytes", type=int, default=4_000_000_000)
    args = parser.parse_args(); load_config(args.config)
    if args.start >= args.end or args.max_derived_bytes <= 0:
        raise SystemExit("invalid horizon or max derived bytes")
    if args.plan_only:
        print(f"PLAN_OK mode=target_row_diff horizon={args.start}..{args.end} max_derived_bytes={args.max_derived_bytes}", flush=True); return
    run_refresh(args.start, args.end, args.max_derived_bytes)


if __name__ == "__main__":
    main()
