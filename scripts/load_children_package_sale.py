#!/usr/bin/env python3
"""Atomically rebuild mart.children_package_sale from the reviewed 1C report logic."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tempfile
import time
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
from psycopg import OperationalError, sql


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry


EXTRACT = ROOT / "sql/marts/children_package_sale_extract.sql"
SOURCE_CONTROL = ROOT / "sql/marts/children_package_sale_erf_source_control.sql"
DDL = ROOT / "sql/marts/children_package_sale_ddl.sql"
RECONCILIATION = ROOT / "sql/tests/children_package_sale_reconciliation.sql"
TABLE = "mart.children_package_sale"
STAGE = "_children_package_sale_stage"
TIMEOUT_SECONDS = 180
BATCH_ATTEMPTS = 3
COLUMNS = (
    "report_row_id, sale_at, sale_date, receipt_status_id, source_sale_club_id, "
    "source_sale_employee_id, club_id, club_name, membership_id, membership_code, "
    "membership_name, membership_purchase_date, membership_activation_date, "
    "membership_start_date, membership_end_date, adult_client_id, adult_client_code, "
    "adult_client_name, child_client_id, child_client_code, child_client_name, "
    "product_id, product_name, package_amount, package_amount_without_discount, "
    "package_count, sold_correctly_flag, movement_kind"
)


class SnapshotRestartRequired(RuntimeError):
    """An exported source snapshot cannot safely be resumed."""


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"],
        "dbname": values["PGDATABASE"], "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
    }
    if sslmode := os.environ.get(prefix + "PGSSLMODE"):
        result["sslmode"] = sslmode
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date.fromordinal(today.toordinal() + 1)


def rendered(path: Path, start: date, end: date, horizon_start: date, horizon_end: date) -> str:
    values = (start, end, horizon_start, horizon_end)
    rendered_sql = path.read_text(encoding="utf-8").strip().rstrip(";")
    for number in range(4, 0, -1):
        rendered_sql = rendered_sql.replace(
            f"${number}::date", f"DATE '{values[number - 1].isoformat()}'"
        )
    return rendered_sql


def statements(path: Path) -> list[str]:
    body = "\n".join(line for line in path.read_text(encoding="utf-8").splitlines()
                     if not line.lstrip().startswith("--"))
    return [statement.strip() for statement in body.split(";") if statement.strip()]


def month_batches(start: date, end: date) -> list[tuple[date, date]]:
    result: list[tuple[date, date]] = []
    current = start
    while current < end:
        next_month = date(current.year + (current.month == 12), current.month % 12 + 1, 1)
        result.append((current, min(next_month, end)))
        current = next_month
    return result


def require_batch_space(directory: Path) -> None:
    if shutil.disk_usage(directory).free < 1_073_741_824:
        raise RuntimeError("Less than 1 GiB is free for the single temporary COPY buffer")


def close_after_failure(connection) -> None:
    if connection is None:
        return
    try:
        connection.rollback()
    except Exception:
        pass
    try:
        connection.close()
    except Exception:
        pass


def source_reader(snapshot_id: str):
    source = connect_with_retry(
        lambda: psycopg.connect(**config("SOURCE_")), endpoint="source"
    )
    try:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute(
                sql.SQL("SET TRANSACTION SNAPSHOT {}").format(sql.Literal(snapshot_id))
            )
            cursor.execute(f"SET LOCAL statement_timeout = '{TIMEOUT_SECONDS}s'")
        return source
    except Exception:
        close_after_failure(source)
        raise


def source_expected(cursor, start: date, end: date, horizon_start: date, horizon_end: date) -> dict[str, object]:
    cursor.execute(rendered(SOURCE_CONTROL, start, end, horizon_start, horizon_end))
    row = cursor.fetchone()
    if row is None:
        raise RuntimeError("Independent source control returned no row")
    columns = [item.name for item in cursor.description]
    expected = dict(zip(columns, row, strict=True))
    required_nonnegative = (
        "child_output_rows", "return_child_output_rows", "duplicate_report_row_ids",
        "child_reference_orphans", "adult_reference_orphans", "access_club_orphans",
        "nullable_access_club_names",
    )
    if any(int(expected[key]) < 0 for key in required_nonnegative):
        raise RuntimeError("Independent source control has an invalid count")
    if int(expected["duplicate_report_row_ids"]) != 0:
        raise RuntimeError("Independent source control found duplicate report_row_id values")
    if int(expected["child_reference_orphans"]) or int(expected["adult_reference_orphans"]):
        raise RuntimeError("Independent source control found mandatory reference orphans")
    if expected["min_sale_date"] is None or expected["max_sale_date"] is None:
        raise RuntimeError("Independent source control has no child-package dates")
    return expected


def copy_source_batch(source, start: date, end: date, horizon_start: date, horizon_end: date, transfer: Path) -> tuple[int, int, float]:
    started = time.monotonic()
    with source.cursor() as cursor, transfer.open("wb") as output:
        with cursor.copy(
            f"COPY ({rendered(EXTRACT, start, end, horizon_start, horizon_end)}) TO STDOUT WITH (FORMAT BINARY)"
        ) as copied:
            for block in copied:
                output.write(block)
        rows = cursor.rowcount
    if rows < 0:
        raise RuntimeError("Source COPY did not report a row count")
    return rows, transfer.stat().st_size, time.monotonic() - started


def prepare_source_batch(snapshot_id: str, start: date, end: date, horizon_start: date, horizon_end: date, directory: Path):
    transfer = directory / f"children_package_sale_{start:%Y%m}.copy"
    for attempt in range(1, BATCH_ATTEMPTS + 1):
        source = None
        transfer.unlink(missing_ok=True)
        try:
            source = source_reader(snapshot_id)
            with source.cursor() as cursor:
                expected = source_expected(cursor, start, end, horizon_start, horizon_end)
            require_batch_space(directory)
            rows, byte_count, elapsed = copy_source_batch(
                source, start, end, horizon_start, horizon_end, transfer
            )
            source.rollback()
            source.close()
            return transfer, rows, byte_count, elapsed, expected
        except OperationalError as error:
            close_after_failure(source)
            transfer.unlink(missing_ok=True)
            print(f"SOURCE_BATCH_RETRY start={start} attempt={attempt}/{BATCH_ATTEMPTS} "
                  f"error={type(error).__name__}", flush=True)
        except Exception:
            close_after_failure(source)
            transfer.unlink(missing_ok=True)
            raise
    raise SnapshotRestartRequired(f"Source batch retry budget exhausted start={start}")


def combine_expected(total: dict[str, object] | None, current: dict[str, object]) -> dict[str, object]:
    if total is None:
        return current.copy()
    result = total.copy()
    for key in ("child_output_rows", "return_child_output_rows", "nullable_access_club_names"):
        result[key] = int(total[key]) + int(current[key])
    for key in ("child_quantity_total", "child_amount_total", "child_return_amount_total"):
        result[key] = Decimal(total[key]) + Decimal(current[key])
    result["min_sale_date"] = min(total["min_sale_date"], current["min_sale_date"])
    result["max_sale_date"] = max(total["max_sale_date"], current["max_sale_date"])
    return result


def require_stage_contract(cursor, start: date, end: date, expected: dict[str, object]) -> None:
    cursor.execute(
        f"""SELECT count(*)::bigint, count(DISTINCT report_row_id)::bigint,
                    count(*) FILTER (WHERE movement_kind = 'Расход')::bigint,
                    coalesce(sum(package_count), 0)::numeric,
                    coalesce(sum(package_amount), 0)::numeric,
                    coalesce(sum(package_amount) FILTER (WHERE movement_kind = 'Расход'), 0)::numeric
             FROM {STAGE}"""
    )
    actual = cursor.fetchone()
    expected_values = (
        int(expected["child_output_rows"]), int(expected["child_output_rows"]),
        int(expected["return_child_output_rows"]), Decimal(expected["child_quantity_total"]),
        Decimal(expected["child_amount_total"]), Decimal(expected["child_return_amount_total"]),
    )
    if actual != expected_values:
        raise RuntimeError(f"Stage differs from independent source controls actual={actual!r}")
    cursor.execute(
        f"""SELECT count(*) FROM {STAGE}
             WHERE sale_date < %s OR sale_date >= %s OR sale_at IS NULL OR receipt_status_id IS NULL
                OR club_id IS NULL OR membership_id IS NULL OR membership_code IS NULL
                OR membership_name IS NULL OR membership_purchase_date IS NULL
                OR membership_activation_date IS NULL OR membership_start_date IS NULL
                OR membership_end_date IS NULL OR adult_client_id IS NULL OR adult_client_code IS NULL
                OR adult_client_name IS NULL OR child_client_id IS NULL OR child_client_code IS NULL
                OR child_client_name IS NULL OR product_id IS NULL OR product_name IS NULL
                OR package_amount IS NULL OR package_amount_without_discount IS NULL
                OR package_count IS NULL OR sold_correctly_flag IS NULL
                OR movement_kind NOT IN ('Приход', 'Расход')""",
        (start, end),
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Stage violates children-package fact contract")


def require_reconciliation(cursor, expected: dict[str, object], start: date, end: date, phase: str) -> None:
    parameters = (
        expected["child_output_rows"], expected["child_output_rows"],
        expected["return_child_output_rows"], expected["child_quantity_total"],
        expected["child_amount_total"], expected["child_return_amount_total"],
        expected["min_sale_date"], expected["max_sale_date"], expected["nullable_access_club_names"],
        start, end,
    )
    reconciliation_sql = RECONCILIATION.read_text(encoding="utf-8")
    numbered_parameters = tuple(
        parameters[int(match.group(1)) - 1]
        for match in re.finditer(r"\$(\d+)", reconciliation_sql)
    )
    reconciliation_sql = re.sub(r"\$\d+", "%s", reconciliation_sql)
    cursor.execute(reconciliation_sql, numbered_parameters)
    failures = [(row[0], row[1], row[2]) for row in cursor.fetchall() if row[4] != "PASS"]
    if failures:
        raise RuntimeError(f"Target reconciliation failed phase={phase}: {failures}")
    print(f"TARGET_RECONCILIATION_PASS phase={phase} controls=11", flush=True)


def target_read_plan(cursor, start: date, end: date) -> tuple[float, int, int]:
    cursor.execute(
        f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) "
        f"SELECT sale_date, club_id, product_id, package_amount, package_count FROM {TABLE} "
        "WHERE sale_date >= %s AND sale_date < %s",
        (start, end),
    )
    plan = cursor.fetchone()[0][0]
    node = plan["Plan"]
    return float(plan["Execution Time"]), int(node.get("Shared Hit Blocks", 0)), int(node.get("Shared Read Blocks", 0))


def run_once(initial: bool) -> tuple[float, int, int]:
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    ddl = statements(DDL)
    if len(ddl) != 2:
        raise RuntimeError("Reviewed DDL statement count changed")
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="children_package_sale_") as temporary_directory:
        directory = Path(temporary_directory)
        owner = connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source")
        target = None
        try:
            with owner.cursor() as cursor:
                cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                cursor.execute(f"SET LOCAL statement_timeout = '{TIMEOUT_SECONDS}s'")
                cursor.execute("SELECT pg_export_snapshot()")
                snapshot_id = cursor.fetchone()[0]
            target = connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart")
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SET LOCAL lock_timeout = '60s'")
                cursor.execute(f"SET LOCAL statement_timeout = '{TIMEOUT_SECONDS}s'")
                cursor.execute("SET LOCAL idle_in_transaction_session_timeout = '240s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.children_package_sale:refresh",))
                cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                exists = cursor.fetchone()[0] is not None
                if initial == exists:
                    raise RuntimeError("Initial/rerun target state does not match requested operation")
                if initial:
                    for statement in ddl:
                        cursor.execute(statement)
                cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                expected_total: dict[str, object] | None = None
                copied_rows = 0
                for batch_start, batch_end in month_batches(start, end):
                    transfer, rows, byte_count, elapsed, expected = prepare_source_batch(
                        snapshot_id, batch_start, batch_end, start, end, directory
                    )
                    try:
                        with cursor.copy(f"COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copied, transfer.open("rb") as input_file:
                            while block := input_file.read(1_048_576):
                                copied.write(block)
                        if cursor.rowcount != rows:
                            raise RuntimeError(f"Target batch COPY differs: {cursor.rowcount} != {rows}")
                    finally:
                        transfer.unlink(missing_ok=True)
                    copied_rows += rows
                    expected_total = combine_expected(expected_total, expected)
                    print(f"BATCH_PASS start={batch_start} end={batch_end} rows={rows} bytes={byte_count} "
                          f"elapsed_seconds={elapsed:.3f} timeout_seconds={TIMEOUT_SECONDS}", flush=True)
                assert expected_total is not None
                require_stage_contract(cursor, start, end, expected_total)
                cursor.execute(f"DELETE FROM {TABLE}")
                cursor.execute(f"INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM {STAGE}")
                require_reconciliation(cursor, expected_total, start, end, "pre_commit")
                target.commit()
            owner.rollback()
            owner.close()
            with target.cursor() as cursor:
                read_ms, hit, read = target_read_plan(cursor, start, end)
            print(f"LOAD_COMMITTED horizon={start}..{end} rows={copied_rows} "
                  f"elapsed_seconds={time.monotonic() - started:.3f}", flush=True)
            return read_ms, hit, read
        except Exception:
            close_after_failure(owner)
            close_after_failure(target)
            raise
        finally:
            if target is not None:
                target.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--initial", action="store_true", help="create and load the approved initial fact")
    parser.add_argument("--rerun", action="store_true", help="perform the approved atomic rerun")
    args = parser.parse_args()
    if args.initial == args.rerun:
        raise SystemExit("Specify exactly one of --initial or --rerun")
    read_ms, hit, read = run_once(initial=args.initial)
    print(f"TARGET_READ_PLAN execution_ms={read_ms:.3f} shared_hit={hit} shared_read={read}", flush=True)


if __name__ == "__main__":
    main()
