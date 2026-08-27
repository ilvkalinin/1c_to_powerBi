#!/usr/bin/env python3
"""Atomically load the M-compatible unconfirmed-service debt movement mart."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
import time
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
import psycopg2


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.load_client_base_snapshot_retention import (  # noqa: E402
    TRANSPORT_CONNECTION_OPTIONS,
    TransportWatchdog,
    close_after_failure,
    config,
)
from scripts.mart_connection import connect_with_retry  # noqa: E402


EXTRACT = ROOT / "sql/marts/unconfirmed_service_debt_movement_extract.sql"
SOURCE_CONTROL = ROOT / "sql/marts/unconfirmed_service_debt_movement_source_control.sql"
DDL = ROOT / "sql/marts/unconfirmed_service_debt_movement_ddl.sql"
REPLACE = ROOT / "sql/marts/unconfirmed_service_debt_movement_target_replace.sql"
RECONCILIATION = ROOT / "sql/tests/unconfirmed_service_debt_movement_reconciliation.sql"
TABLE = "mart.unconfirmed_service_debt_movement"
STAGE = "_unconfirmed_service_debt_movement_stage"
COLUMNS = (
    "debt_event_at, recorder_type, recorder_id, recorder_line_no, record_kind, "
    "client_key, client_code, client_name, club_id, club_name, prebooking_id, "
    "service_id, service_name, employee_id, employee_name, service_start_at, "
    "service_end_at, quantity_delta, amount_delta"
)
TRANSPORT_TIMEOUT_SECONDS = 180
SOURCE_BATCH_MAX_ATTEMPTS = 3
TRANSPORT_PREFLIGHT_SAMPLES = 3
TRANSPORT_PREFLIGHT_INTERVAL_SECONDS = 10


class TransportRestartRequired(RuntimeError):
    """The atomic source snapshot or target transaction cannot be continued."""


def source_config(application_name: str) -> dict[str, object]:
    return config("SOURCE_", application_name) | TRANSPORT_CONNECTION_OPTIONS


def mart_config(application_name: str) -> dict[str, object]:
    return config("MART_", application_name) | TRANSPORT_CONNECTION_OPTIONS


def connect_source_with_retry(application_name: str):
    last_error: Exception | None = None
    for retry in range(6):
        try:
            return psycopg2.connect(**source_config(application_name))
        except psycopg2.OperationalError as error:
            last_error = error
            if retry == 5:
                break
            print(f"CONNECTION_RETRY endpoint=source retry={retry + 1}/5 delay_seconds=5", flush=True)
            time.sleep(5)
    assert last_error is not None
    raise last_error


def transport_preflight(endpoint: str) -> None:
    for sample in range(1, TRANSPORT_PREFLIGHT_SAMPLES + 1):
        if endpoint == "source":
            connection = connect_source_with_retry("unconfirmed_service_debt_source_preflight")
        else:
            connection = connect_with_retry(
                lambda: psycopg.connect(**mart_config("unconfirmed_service_debt_target_preflight")),
                endpoint="mart",
            )
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            print(f"TRANSPORT_PREFLIGHT_PASS endpoint={endpoint} sample={sample}/{TRANSPORT_PREFLIGHT_SAMPLES}", flush=True)
        finally:
            connection.close()
        if sample < TRANSPORT_PREFLIGHT_SAMPLES:
            time.sleep(TRANSPORT_PREFLIGHT_INTERVAL_SECONDS)


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date.fromordinal(today.toordinal() + 1)


def rendered(path: Path, start: date, end: date) -> str:
    return (
        path.read_text(encoding="utf-8").strip().rstrip(";")
        .replace("$1::timestamp", f"TIMESTAMP '{start.isoformat()} 00:00:00'")
        .replace("$2::timestamp", f"TIMESTAMP '{end.isoformat()} 00:00:00'")
    )


def statements(path: Path, start: date, end: date) -> list[str]:
    body = "\n".join(line for line in rendered(path, start, end).splitlines() if not line.lstrip().startswith("--"))
    result: list[str] = []
    current: list[str] = []
    quoted = False
    for index, char in enumerate(body):
        current.append(char)
        if char == "'" and (index + 1 == len(body) or body[index + 1] != "'"):
            quoted = not quoted
        if char == ";" and not quoted:
            statement = "".join(current[:-1]).strip()
            if statement and statement.upper() not in {"BEGIN", "COMMIT"}:
                result.append(statement)
            current = []
    tail = "".join(current).strip()
    if tail and tail.upper() not in {"BEGIN", "COMMIT"}:
        result.append(tail)
    return result


def month_batches(start: date, end: date) -> list[tuple[date, date]]:
    batches: list[tuple[date, date]] = []
    current = start
    while current < end:
        next_month = date(current.year + (current.month == 12), current.month % 12 + 1, 1)
        batches.append((current, min(next_month, end)))
        current = next_month
    return batches


def require_batch_space(directory: Path) -> None:
    if shutil.disk_usage(directory).free < 1_073_741_824:
        raise RuntimeError("Less than 1 GiB is free for the single COPY buffer")


def source_reader(snapshot_id: str):
    connection = connect_source_with_retry("unconfirmed_service_debt_source_reader")
    try:
        with connection.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET TRANSACTION SNAPSHOT %s", (snapshot_id,))
            cursor.execute("SET LOCAL statement_timeout = '180000'")
        return connection
    except Exception:
        connection.close()
        raise


def source_admission_available() -> bool:
    try:
        connection = psycopg2.connect(**source_config("unconfirmed_service_debt_source_admission_probe"))
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            return True
        finally:
            connection.close()
    except psycopg2.Error as error:
        print(f"SOURCE_ADMISSION_UNAVAILABLE error={type(error).__name__}", flush=True)
        return False


def source_expected(cursor, start: date, end: date) -> dict[str, object]:
    cursor.execute(rendered(SOURCE_CONTROL, start, end))
    row = cursor.fetchone()
    if row is None:
        raise RuntimeError("Independent source control returned no row")
    rows, keys, invalid_paths, amount, min_at, max_at = row
    if rows < 0 or rows != keys or amount is None or min_at is None or max_at is None or invalid_paths < 0:
        raise RuntimeError("Independent source control violates its declared domain")
    return {"rows": int(rows), "keys": int(keys), "invalid_paths": int(invalid_paths),
            "amount": Decimal(amount), "min_at": min_at, "max_at": max_at}


def copy_source_batch(source, start: date, end: date, transfer: Path) -> tuple[int | None, int, float]:
    started = time.monotonic()
    with TransportWatchdog(source, "source_binary_copy"), source.cursor() as cursor, transfer.open("wb") as output:
        cursor.copy_expert(f"COPY ({rendered(EXTRACT, start, end)}) TO STDOUT WITH (FORMAT BINARY)", output)
        rows = cursor.rowcount if cursor.rowcount >= 0 else None
    return rows, transfer.stat().st_size, time.monotonic() - started


def prepare_source_batch(snapshot_id: str, start: date, end: date, directory: Path) -> tuple[Path, int | None, int, float, dict[str, object]]:
    transfer = directory / f"unconfirmed_service_debt_{start:%Y%m}.copy"
    for attempt in range(1, SOURCE_BATCH_MAX_ATTEMPTS + 1):
        transfer.unlink(missing_ok=True)
        source = None
        try:
            source = source_reader(snapshot_id)
            with source.cursor() as cursor:
                expected = source_expected(cursor, start, end)
            require_batch_space(directory)
            rows, byte_count, elapsed = copy_source_batch(source, start, end, transfer)
            source.rollback()
            source.close()
            return transfer, rows, byte_count, elapsed, expected
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as error:
            if source is not None:
                close_after_failure("source_batch", source)
            transfer.unlink(missing_ok=True)
            print(f"SOURCE_WORKER_RETRY start={start} attempt={attempt} error={type(error).__name__}", flush=True)
            if not source_admission_available():
                raise TransportRestartRequired(f"Source admission unavailable start={start}") from error
        except Exception:
            if source is not None:
                close_after_failure("source_batch", source)
            transfer.unlink(missing_ok=True)
            raise
    raise TransportRestartRequired(f"Source batch exhausted retries start={start}")


def copy_prepared_batch(cursor, target, transfer: Path, source_rows: int | None, start: date, end: date,
                        byte_count: int, elapsed: float, expected: dict[str, object]) -> int:
    try:
        with TransportWatchdog(target, "target_binary_copy"), cursor.copy(
            f"COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
        ) as copied, transfer.open("rb") as input_file:
            while block := input_file.read(1_048_576):
                copied.write(block)
        if source_rows is not None and cursor.rowcount != source_rows:
            raise RuntimeError(f"Target COPY count differs: {cursor.rowcount} != {source_rows}")
        print(f"BATCH_PASS start={start} end={end} control_rows={expected['rows']} "
              f"invalid_branch_paths={expected['invalid_paths']} rows={cursor.rowcount} "
              f"bytes={byte_count} elapsed_seconds={elapsed:.3f}", flush=True)
        return cursor.rowcount
    finally:
        transfer.unlink(missing_ok=True)


def combine_expected(total: dict[str, object] | None, current: dict[str, object]) -> dict[str, object]:
    if total is None:
        return current.copy()
    return {
        "rows": int(total["rows"]) + int(current["rows"]),
        "keys": int(total["keys"]) + int(current["keys"]),
        "invalid_paths": int(total["invalid_paths"]) + int(current["invalid_paths"]),
        "amount": Decimal(total["amount"]) + Decimal(current["amount"]),
        "min_at": min(total["min_at"], current["min_at"]),
        "max_at": max(total["max_at"], current["max_at"]),
    }


def require_stage_contract(cursor, start: date, end: date, expected: dict[str, object]) -> None:
    cursor.execute(
        f"SELECT count(*)::bigint, count(DISTINCT (debt_event_at, recorder_type, recorder_id, recorder_line_no))::bigint, "
        f"coalesce(sum(amount_delta),0)::numeric(20,2), min(debt_event_at), max(debt_event_at) FROM {STAGE}"
    )
    actual = cursor.fetchone()
    values = (int(expected["rows"]), int(expected["keys"]), Decimal(expected["amount"]), expected["min_at"], expected["max_at"])
    if actual != values:
        raise RuntimeError(f"Stage differs from independent source controls actual={actual!r}")
    cursor.execute(
        f"SELECT count(*) FROM {STAGE} WHERE debt_event_at < %s OR debt_event_at >= %s "
        "OR debt_event_at IS NULL OR recorder_type IS NULL OR recorder_id IS NULL "
        "OR recorder_line_no IS NULL OR record_kind NOT IN (0,1) OR client_key IS NULL "
        "OR club_id IS NULL OR prebooking_id IS NULL OR service_id IS NULL OR employee_id IS NULL "
        "OR service_start_at IS NULL OR service_end_at IS NULL OR quantity_delta IS NULL OR amount_delta IS NULL",
        (start, end),
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Stage violates target fact contract")


def require_reconciliation(cursor, expected: dict[str, object], start: date, end: date, phase: str) -> None:
    parameters = (expected["rows"], expected["keys"], expected["amount"], expected["min_at"], expected["max_at"], start, end)
    cursor.execute(RECONCILIATION.read_text(encoding="utf-8"), parameters)
    failures = [(row[0], row[3]) for row in cursor.fetchall() if row[4] != "PASS"]
    if failures:
        raise RuntimeError(f"Target reconciliation failed phase={phase}: {failures}")
    print(f"TARGET_RECONCILIATION_PASS phase={phase} controls=7", flush=True)


def target_read_plan(cursor, start: date, end: date) -> tuple[float, int, int]:
    cursor.execute(
        f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT debt_event_at, client_code, amount_delta "
        f"FROM {TABLE} WHERE debt_event_at >= %s AND debt_event_at < %s",
        (start, end),
    )
    plan = cursor.fetchone()[0][0]
    node = plan["Plan"]
    return float(plan["Execution Time"]), int(node.get("Shared Hit Blocks", 0)), int(node.get("Shared Read Blocks", 0))


def require_target_state(cursor, initial: bool) -> None:
    cursor.execute("SELECT to_regclass(%s)", (TABLE,))
    exists = cursor.fetchone()[0] is not None
    if initial and exists:
        raise RuntimeError("Initial load requires target fact to be absent")
    if not initial and not exists:
        raise RuntimeError("Rerun requires target fact to exist")


def run_once(initial: bool) -> None:
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    ddl, replace = statements(DDL, start, end), statements(REPLACE, start, end)
    if (len(ddl), len(replace)) != (1, 2):
        raise RuntimeError("Reviewed DDL or target-replace statement count changed")
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="unconfirmed_service_debt_") as temp_directory:
        directory = Path(temp_directory)
        transport_preflight("source")
        transport_preflight("mart")
        source_owner = connect_source_with_retry("unconfirmed_service_debt_source_owner")
        target = None
        try:
            with source_owner.cursor() as source_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                source_cursor.execute("SELECT pg_export_snapshot()")
                snapshot_id = source_cursor.fetchone()[0]
            print(f"SOURCE_SNAPSHOT horizon={start}..{end} control_mode=monthly_before_copy "
                  "reader_lifecycle=reconnect_per_month transport_buffer=single_month_binary_copy", flush=True)
            target = connect_with_retry(
                lambda: psycopg.connect(**mart_config("unconfirmed_service_debt_target")), endpoint="mart"
            )
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SET LOCAL lock_timeout = '60s'")
                cursor.execute("SET LOCAL idle_in_transaction_session_timeout = '240s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.unconfirmed_service_debt_movement:refresh",))
                require_target_state(cursor, initial)
                if initial:
                    cursor.execute(ddl[0])
                cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                expected_total: dict[str, object] | None = None
                copied_rows = 0
                for batch_start, batch_end in month_batches(start, end):
                    transfer, source_rows, byte_count, elapsed, expected = prepare_source_batch(
                        snapshot_id, batch_start, batch_end, directory
                    )
                    copied_rows += copy_prepared_batch(
                        cursor, target, transfer, source_rows, batch_start, batch_end, byte_count, elapsed, expected
                    )
                    expected_total = combine_expected(expected_total, expected)
                assert expected_total is not None
                print(
                    f"SOURCE_SNAPSHOT_CONTROL rows={expected_total['rows']} keys={expected_total['keys']} "
                    f"amount={expected_total['amount']} min_event_at={expected_total['min_at']} "
                    f"max_event_at={expected_total['max_at']} "
                    f"invalid_branch_paths={expected_total['invalid_paths']}",
                    flush=True,
                )
                require_stage_contract(cursor, start, end, expected_total)
                for statement in replace:
                    cursor.execute(statement)
                require_reconciliation(cursor, expected_total, start, end, "pre_commit")
                target.commit()
            source_owner.rollback()
            source_owner.close()
            print(f"TARGET_COMMIT rows={copied_rows} invalid_branch_paths={expected_total['invalid_paths']} "
                  f"elapsed_seconds={time.monotonic() - started:.3f}", flush=True)
            with target.cursor() as cursor:
                require_reconciliation(cursor, expected_total, start, end, "post_commit")
                plan_ms, hit, read = target_read_plan(cursor, start, end)
            print(f"TARGET_READ_PLAN execution_ms={plan_ms:.3f} shared_hit={hit} shared_read={read}", flush=True)
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
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--initial-load", action="store_true")
    mode.add_argument("--rerun", action="store_true")
    args = parser.parse_args()
    try:
        run_once(args.initial_load)
    except (TransportRestartRequired, psycopg.OperationalError, psycopg.InterfaceError,
            psycopg2.OperationalError, psycopg2.InterfaceError) as error:
        print(f"RERUN_TRANSPORT_FAILURE error={type(error).__name__} automatic_full_restart=disabled", flush=True)
        raise


if __name__ == "__main__":
    main()
