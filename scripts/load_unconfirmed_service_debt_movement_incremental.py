#!/usr/bin/env python3
"""Run the separately configured bounded-window debt movement refresh."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from datetime import date
from decimal import Decimal
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_unconfirmed_service_debt_movement import (
    COLUMNS,
    EXTRACT,
    STAGE,
    TABLE,
    TransportRestartRequired,
    br003_horizon,
    close_after_failure,
    combine_expected,
    connect_source_with_retry,
    copy_prepared_batch,
    mart_config,
    month_batches,
    prepare_source_batch,
    rendered,
    require_reconciliation,
    require_stage_contract,
    statements,
    transport_preflight,
)
from scripts.mart_connection import connect_with_retry


DEFAULT_CONFIG = ROOT / "config/unconfirmed_service_debt_movement_incremental.json"
REPLACE = ROOT / "sql/marts/unconfirmed_service_debt_movement_incremental_target_replace.sql"


def subtract_months(month_start: date, months: int) -> date:
    absolute = month_start.year * 12 + month_start.month - 1 - months
    return date(absolute // 12, absolute % 12 + 1, 1)


def load_config(path: Path) -> tuple[date, int]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("object") != TABLE or payload.get("mode") != "bounded_sliding_window":
        raise RuntimeError("Incremental config does not target the reviewed mart/mode")
    as_of_date = date.fromisoformat(payload["as_of_date"])
    months = int(payload["months_in_window"])
    if months < 1 or months > 12:
        raise RuntimeError("months_in_window must be in 1..12")
    if payload.get("watermark") is not None or payload.get("incremental_sla") is not None:
        raise RuntimeError("Unvalidated watermark or incremental SLA is forbidden")
    return as_of_date, months


def boundaries(as_of_date: date, months: int) -> tuple[date, date, date]:
    horizon_start, horizon_end = br003_horizon(as_of_date)
    current_month = date(as_of_date.year, as_of_date.month, 1)
    window_start = max(horizon_start, subtract_months(current_month, months - 1))
    return horizon_start, window_start, horizon_end


def source_plan(start: date, end: date) -> dict[str, object]:
    source = connect_source_with_retry("unconfirmed_service_debt_incremental_plan")
    try:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout = '180000'")
            cursor.execute(f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {rendered(EXTRACT, start, end)}")
            plan = cursor.fetchone()[0][0]
        source.rollback()
        node = plan["Plan"]
        return {
            "start": start.isoformat(), "end": end.isoformat(),
            "rows": int(node.get("Actual Rows", 0)),
            "execution_ms": float(plan["Execution Time"]),
            "shared_hit": int(node.get("Shared Hit Blocks", 0)),
            "shared_read": int(node.get("Shared Read Blocks", 0)),
            "temp_read": int(node.get("Temp Read Blocks", 0)),
            "temp_written": int(node.get("Temp Written Blocks", 0)),
        }
    finally:
        source.close()


def plan_ladder(window_start: date, window_end: date) -> None:
    ends = month_batches(window_start, window_end)
    for count in range(1, len(ends) + 1):
        result = source_plan(window_start, ends[count - 1][1])
        print("SOURCE_PLAN " + json.dumps(result, sort_keys=True), flush=True)


def preserved_expected(cursor, horizon_start: date, window_start: date) -> dict[str, object] | None:
    cursor.execute(
        f"SELECT count(*)::bigint, count(DISTINCT (debt_event_at, recorder_type, recorder_id, recorder_line_no))::bigint, "
        f"coalesce(sum(amount_delta),0)::numeric(20,2), min(debt_event_at), max(debt_event_at) "
        f"FROM {TABLE} WHERE debt_event_at >= %s AND debt_event_at < %s",
        (horizon_start, window_start),
    )
    rows, keys, amount, min_at, max_at = cursor.fetchone()
    if rows == 0:
        return None
    return {"rows": int(rows), "keys": int(keys), "invalid_paths": 0,
            "amount": Decimal(amount), "min_at": min_at, "max_at": max_at}


def run_refresh(horizon_start: date, window_start: date, window_end: date) -> None:
    replace = statements(REPLACE, horizon_start, window_end)
    if len(replace) != 2:
        raise RuntimeError("Reviewed incremental replace statement count changed")
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="unconfirmed_service_debt_incremental_") as temp_directory:
        directory = Path(temp_directory)
        transport_preflight("source")
        transport_preflight("mart")
        source_owner = connect_source_with_retry("unconfirmed_service_debt_incremental_owner")
        target = None
        try:
            with source_owner.cursor() as source_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                source_cursor.execute("SELECT pg_export_snapshot()")
                snapshot_id = source_cursor.fetchone()[0]
            print(f"SOURCE_SNAPSHOT horizon={horizon_start}..{window_end} window={window_start}..{window_end}", flush=True)
            target = connect_with_retry(
                lambda: psycopg.connect(**mart_config("unconfirmed_service_debt_incremental_target")),
                endpoint="mart",
            )
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SET LOCAL lock_timeout = '60s'")
                cursor.execute("SET LOCAL idle_in_transaction_session_timeout = '240s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (f"{TABLE}:refresh",))
                cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                if cursor.fetchone()[0] is None:
                    raise RuntimeError("Incremental refresh requires the existing target fact")
                preserved = preserved_expected(cursor, horizon_start, window_start)
                cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                window_expected = None
                copied_rows = 0
                for batch_start, batch_end in month_batches(window_start, window_end):
                    transfer, source_rows, byte_count, elapsed, expected = prepare_source_batch(
                        snapshot_id, batch_start, batch_end, directory
                    )
                    copied_rows += copy_prepared_batch(
                        cursor, target, transfer, source_rows, batch_start, batch_end,
                        byte_count, elapsed, expected
                    )
                    window_expected = combine_expected(window_expected, expected)
                if window_expected is None:
                    raise RuntimeError("Configured window produced no source batches")
                require_stage_contract(cursor, window_start, window_end, window_expected)
                cursor.execute(replace[0], (horizon_start, window_end, window_start, window_end))
                cursor.execute(replace[1])
                total_expected = combine_expected(preserved, window_expected)
                require_reconciliation(cursor, total_expected, horizon_start, window_end, "pre_commit")
                target.commit()
            source_owner.rollback()
            source_owner.close()
            elapsed = time.monotonic() - started
            print(f"TARGET_COMMIT window_rows={copied_rows} elapsed_seconds={elapsed:.3f}", flush=True)
            with target.cursor() as cursor:
                require_reconciliation(cursor, total_expected, horizon_start, window_end, "post_commit")
            print(f"INCREMENTAL_REFRESH_PASS elapsed_seconds={elapsed:.3f}", flush=True)
        except Exception:
            if target is not None:
                close_after_failure("target", target)
            raise
        finally:
            if source_owner is not None and not source_owner.closed:
                close_after_failure("source_owner", source_owner)
            if target is not None and not target.closed:
                target.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan-only", action="store_true")
    mode.add_argument("--run", action="store_true")
    args = parser.parse_args()
    as_of_date, months = load_config(args.config)
    horizon_start, window_start, window_end = boundaries(as_of_date, months)
    print(f"CONFIG as_of_date={as_of_date} horizon={horizon_start}..{window_end} window={window_start}..{window_end}")
    if args.plan_only:
        plan_ladder(window_start, window_end)
    else:
        run_refresh(horizon_start, window_start, window_end)


if __name__ == "__main__":
    main()
