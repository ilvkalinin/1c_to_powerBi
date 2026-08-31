#!/usr/bin/env python3
"""Atomically load the approved mart.renewal_management_contract full refresh."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tempfile
from datetime import date
from pathlib import Path

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.mart_connection import connect_with_retry


DDL = ROOT / "sql/marts/renewal_management_contract_ddl.sql"
EXTRACT = ROOT / "sql/marts/renewal_management_contract_source_extract.sql"
SOURCE_CONTROLS = ROOT / "sql/marts/renewal_management_contract_source_controls.sql"
RECONCILIATION = ROOT / "sql/tests/renewal_management_contract_reconciliation.sql"
TARGET = "mart.renewal_management_contract"
COLUMNS = (
    "expiring_contract_id, expiring_contract_code, client_id, client_code, client_name, client_phone, "
    "birth_date, membership_start_date, membership_end_date, contract_end_month, membership_term_days, "
    "access_club_id, purchase_price, visit_count, usage_rate, average_monthly_visits, "
    "renewed_by_month_close_flag, renewed_current_flag, next_contract_id, next_contract_code, "
    "renewal_activation_date, next_contract_start_date, next_contract_term_days, renewal_type, "
    "renewal_lead_lag_days, return_days, return_bucket, current_rating, current_tenure, "
    "last_interaction_at, last_interaction_type, current_funnel_stage, current_fail_reason"
)
MIN_FREE_BYTES = 1 << 30
MAX_COPY_BYTES = 1 << 30
SOURCE_STATEMENT_TIMEOUT_SECONDS = 300


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"], "dbname": values["PGDATABASE"],
        "user": values["PGUSER"], "password": values["PGPASSWORD"], "connect_timeout": "15",
    }
    if sslmode := os.environ.get(prefix + "PGSSLMODE"):
        result["sslmode"] = sslmode
    return result


def current_m_horizon(today: date) -> tuple[date, date]:
    """Exact legacy M predicate: end > 2024-01-01 and <= month_start + 6m - 1d."""
    month = today.month + 6
    return date(2024, 1, 2), date(today.year + (month - 1) // 12, (month - 1) % 12 + 1, 1)


def render(query: str, start: date, end: date) -> str:
    return (query.replace("$1::date", f"DATE '{start.isoformat()}'")
                 .replace("$2::date", f"DATE '{end.isoformat()}'"))


def ddl_without_transaction() -> str:
    text = DDL.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^BEGIN;\s*", "", text, count=1)
    text = re.sub(r"(?m)^COMMIT;\s*$", "", text, count=1)
    if f"CREATE TABLE {TARGET}" not in text:
        raise RuntimeError("Unexpected reviewed DDL")
    return text


def relation_exists(cursor) -> bool:
    cursor.execute("SELECT to_regclass(%s) IS NOT NULL", (TARGET,))
    return cursor.fetchone()[0]


def source_controls(cursor, start: date, end: date) -> tuple:
    query = render(SOURCE_CONTROLS.read_text(encoding="utf-8").strip().rstrip(";"), start, end)
    cursor.execute(query)
    result = cursor.fetchone()
    if result is None or result[0] is None:
        raise RuntimeError("Independent source controls returned no result")
    return result


def copy_source(cursor, query: str, path: Path) -> int:
    with path.open("wb") as output, cursor.copy(f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)") as copy:
        while block := copy.read():
            output.write(block)
    return cursor.rowcount


def copy_target(cursor, path: Path, expected_rows: int) -> None:
    with cursor.copy(f"COPY {TARGET} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copy:
        with path.open("rb") as source:
            while block := source.read(1_048_576):
                copy.write(block)
    if cursor.rowcount != expected_rows:
        raise RuntimeError(f"Target COPY row count differs: {cursor.rowcount} != {expected_rows}")


def reconciliation_statements(expected: tuple) -> list[str]:
    values = {
        "$1::bigint": str(expected[0]), "$2::bigint": str(expected[1]),
        "$3::date": f"DATE '{expected[2].isoformat()}'", "$4::date": f"DATE '{expected[3].isoformat()}'",
        "$5::numeric": str(expected[4]), "$6::bigint": str(expected[5]),
        "$7::bigint": str(expected[6]), "$8::bigint": str(expected[7]),
        "$9::bigint": str(expected[8]), "$10::bigint": str(expected[9]),
    }
    text = RECONCILIATION.read_text(encoding="utf-8")
    for token, replacement in values.items():
        text = text.replace(token, replacement)
    return [part.strip().rstrip(";") for part in re.split(r"(?m)(?=-- RM-R\d+)", text)
            if part.strip().startswith("-- RM-R")]


def require_reconciliation(cursor, expected: tuple) -> None:
    statements = reconciliation_statements(expected)
    if len(statements) != 5:
        raise RuntimeError(f"Unexpected reconciliation statement count: {len(statements)}")
    results: list[tuple] = []
    for ordinal, statement in enumerate(statements, 1):
        cursor.execute(statement)
        results.append(cursor.fetchone())
        print(f"RECONCILIATION_CONTROL_DONE id=RM-R{ordinal:02d}", flush=True)
    if not results[0][-1] or any(results[1]) or any(results[2]) or any(results[3]) or any(results[4]):
        raise RuntimeError(f"Reconciliation failed: {results}")
    print("RECONCILIATION_PASS RM-R01—RM-R05", flush=True)


def load(mode: str, start: date, end: date) -> None:
    extract = render(EXTRACT.read_text(encoding="utf-8").strip().rstrip(";"), start, end)
    with tempfile.TemporaryDirectory(prefix="renewal_management_contract_") as directory:
        directory_path = Path(directory)
        free_bytes = shutil.disk_usage(directory_path).free
        if free_bytes < MIN_FREE_BYTES:
            raise RuntimeError(f"Insufficient temporary transport space: {free_bytes} bytes")
        path = directory_path / "renewal_management_contract.copy"
        with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source:
            try:
                with source.cursor() as source_cursor:
                    source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                    # The source control and COPY are separate statements.  The
                    # 180-second limit observed during the operational rerun was
                    # below the measured end-to-end source phase, while the
                    # reviewed transport remains bounded by the wrapper timeout.
                    source_cursor.execute(
                        f"SET LOCAL statement_timeout='{SOURCE_STATEMENT_TIMEOUT_SECONDS}s'"
                    )
                    expected = source_controls(source_cursor, start, end)
                    source_rows = copy_source(source_cursor, extract, path)
                    if source_rows != expected[0]:
                        raise RuntimeError(f"Independent source rows differ from COPY: {source_rows} != {expected[0]}")
                    source.rollback()
            except Exception:
                source.rollback()
                raise
        copied_bytes = path.stat().st_size
        if copied_bytes > MAX_COPY_BYTES:
            raise RuntimeError(f"Transport buffer exceeds cap: {copied_bytes} bytes")
        print(f"SOURCE_COPY_COMPLETE rows={source_rows} bytes={copied_bytes} free_before={free_bytes}", flush=True)
        with connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
            try:
                with target.cursor() as target_cursor:
                    target_cursor.execute("BEGIN")
                    exists = relation_exists(target_cursor)
                    if mode == "apply":
                        if exists:
                            raise RuntimeError(f"Initial DDL requires absent target: {TARGET}")
                        target_cursor.execute(ddl_without_transaction())
                        print("TARGET_DDL_READY", flush=True)
                    else:
                        if not exists:
                            raise RuntimeError(f"Rebuild requires existing target: {TARGET}")
                        target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET + ":refresh",))
                        target_cursor.execute(f"TRUNCATE TABLE {TARGET}")
                        print("TARGET_TRUNCATE_COMPLETE", flush=True)
                    copy_target(target_cursor, path, source_rows)
                    require_reconciliation(target_cursor, expected)
                    target.commit()
                    print("TARGET_COMMIT_PASS", flush=True)
            except Exception:
                target.rollback()
                raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="perform approved initial DDL and load")
    parser.add_argument("--rebuild", action="store_true", help="perform approved full atomic rebuild")
    parser.add_argument("--today", type=date.fromisoformat, default=date.today(), help="test current-M horizon")
    args = parser.parse_args()
    if args.apply == args.rebuild:
        parser.error("choose exactly one of --apply or --rebuild")
    start, end = current_m_horizon(args.today)
    print(f"CURRENT_M_HORIZON start={start} end={end}", flush=True)
    load("apply" if args.apply else "rebuild", start, end)


if __name__ == "__main__":
    main()
