#!/usr/bin/env python3
"""Atomically load the approved administrator-bookings document fact."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.mart_connection import connect_with_retry


DDL = ROOT / "sql/marts/administrator_bookings_daily_ddl.sql"
EXTRACT = ROOT / "sql/marts/administrator_bookings_daily_extract.sql"
CONTROLS = ROOT / "sql/marts/administrator_bookings_daily_source_controls.sql"
RECONCILIATION = ROOT / "sql/tests/administrator_bookings_daily_reconciliation.sql"
TARGET = "mart.administrator_bookings_daily"
COLUMNS = (
    "booking_source, booking_id, booking_created_date, lesson_date, lesson_end_date, club_id, "
    "booking_author_id, author_position_id, service_id, training_format_id, booking_count, revenue_amount"
)


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


def br003_horizon(today: date) -> tuple[date, date]:
    start_year = today.year - (2 if today.month <= 3 else 1)
    return date(start_year, 1, 1), today + timedelta(days=1)


def render(query: str, start: date, end: date) -> str:
    return query.replace("$1::date", f"DATE '{start.isoformat()}'").replace(
        "$2::date", f"DATE '{end.isoformat()}'"
    )


def sections(path: Path, expected: set[str]) -> dict[str, str]:
    parts = re.split(r"(?m)^-- name: ([a-z_]+)\n", path.read_text(encoding="utf-8"))
    result = {parts[index]: parts[index + 1].strip().rstrip(";") for index in range(1, len(parts), 2)}
    if set(result) != expected:
        raise RuntimeError(f"Unexpected sections in {path.name}: {sorted(result)}")
    return result


def ddl_without_transaction() -> str:
    text = DDL.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^BEGIN;\s*", "", text, count=1)
    text = re.sub(r"(?m)^COMMIT;\s*$", "", text, count=1)
    if "CREATE TABLE mart.administrator_bookings_daily" not in text:
        raise RuntimeError("Unexpected reviewed DDL")
    return text


def month_windows(start: date, end: date):
    current = start
    while current < end:
        next_month = date(current.year + (current.month == 12), (current.month % 12) + 1, 1)
        yield current, min(next_month, end)
        current = next_month


def source_controls(cursor, start: date, end: date) -> list[dict]:
    queries = sections(CONTROLS, {"expected_totals", "source_invariants"})
    cursor.execute(render(queries["expected_totals"], start, end))
    expected = cursor.fetchall()
    cursor.execute(render(queries["source_invariants"], start, end))
    invariants = cursor.fetchone()
    if not expected or any(value != 0 for value in invariants.values()):
        raise RuntimeError(f"Source controls failed: expected={expected}, invariants={invariants}")
    if {row["booking_source"] for row in expected} != {"group", "prebooking"}:
        raise RuntimeError(f"Unexpected source branches: {expected}")
    return expected


def copy_source_month(source_cursor, query: str, path: Path) -> int:
    with path.open("wb") as output, source_cursor.copy(f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)") as copy:
        while block := copy.read():
            output.write(block)
    return source_cursor.rowcount


def copy_target_month(target_cursor, path: Path, expected_rows: int) -> None:
    with target_cursor.copy(f"COPY {TARGET} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copy:
        with path.open("rb") as input_file:
            while block := input_file.read(1_048_576):
                copy.write(block)
    if target_cursor.rowcount != expected_rows:
        raise RuntimeError(f"Target COPY total differs: {target_cursor.rowcount} != {expected_rows}")


def copy_source_to_target(source_cursor, target_cursor, start: date, end: date) -> int:
    query_template = EXTRACT.read_text(encoding="utf-8").strip().rstrip(";")
    copied_rows = 0
    with tempfile.TemporaryDirectory(prefix="administrator_bookings_daily_") as directory:
        directory_path = Path(directory)
        for batch_start, batch_end in month_windows(start, end):
            query = render(query_template, batch_start, batch_end)
            path = directory_path / f"{batch_start.isoformat()}.copy"
            source_rows = copy_source_month(source_cursor, query, path)
            copy_target_month(target_cursor, path, source_rows)
            copied_rows += source_rows
            print(
                f"SOURCE_MONTH_COPY_COMPLETE start={batch_start} end={batch_end} "
                f"rows={source_rows} bytes={path.stat().st_size}", flush=True,
            )
    return copied_rows


def sql_values(expected: list[dict]) -> str:
    rows = []
    for row in expected:
        rows.append(
            "(" + ", ".join((
                f"'{row['booking_source']}'",
                str(int(row["expected_rows"])),
                str(int(row["expected_booking_count"])),
                str(Decimal(row["expected_revenue_amount"])),
                f"DATE '{row['min_lesson_date']}'",
                f"DATE '{row['max_lesson_date']}'",
            )) + ")"
        )
    return ", ".join(rows)


def reconciliation_statements(expected: list[dict], start: date, end: date) -> list[str]:
    text = RECONCILIATION.read_text(encoding="utf-8")
    text = (text.replace("@EXPECTED_SOURCE_VALUES", sql_values(expected))
                 .replace("@START_DATE", f"DATE '{start.isoformat()}'")
                 .replace("@END_DATE", f"DATE '{end.isoformat()}'"))
    return [part.strip().rstrip(";") for part in re.split(r"(?m)(?=-- AB-R\d+)", text)
            if part.strip().startswith("-- AB-R")]


def require_reconciliation(cursor, expected: list[dict], start: date, end: date, copied_rows: int) -> None:
    if copied_rows != sum(int(row["expected_rows"]) for row in expected):
        raise RuntimeError(f"Source COPY rows differ from independent controls: {copied_rows} != {expected}")
    statements = reconciliation_statements(expected, start, end)
    if len(statements) != 6:
        raise RuntimeError(f"Unexpected reconciliation statement count: {len(statements)}")
    cursor.execute(statements[0])
    totals = cursor.fetchall()
    if len(totals) != 2 or not all(row[-1] for row in totals):
        raise RuntimeError(f"AB-R01 failed: {totals}")
    for index, statement in enumerate(statements[1:], 2):
        cursor.execute(statement)
        row = cursor.fetchone()
        if any(value != 0 for value in row):
            raise RuntimeError(f"AB-R{index:02d} failed: {row}")
        print(f"RECONCILIATION_CONTROL_DONE id=AB-R{index:02d}", flush=True)
    print("RECONCILIATION_PASS AB-R01—AB-R06", flush=True)


def relation_exists(cursor) -> bool:
    cursor.execute("SELECT to_regclass('mart.administrator_bookings_daily') IS NOT NULL")
    return cursor.fetchone()[0]


def load(mode: str, start: date, end: date) -> None:
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        try:
            with source.cursor(row_factory=psycopg.rows.dict_row) as source_cursor, target.cursor() as target_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                expected = source_controls(source_cursor, start, end)
                target_cursor.execute("BEGIN")
                target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.administrator_bookings_daily:refresh",))
                exists = relation_exists(target_cursor)
                if mode == "apply":
                    if exists:
                        raise RuntimeError(f"Initial DDL requires absent target: {TARGET}")
                    target_cursor.execute(ddl_without_transaction())
                    print("TARGET_DDL_READY", flush=True)
                elif not exists:
                    raise RuntimeError(f"Rebuild requires existing target: {TARGET}")
                else:
                    target_cursor.execute(f"TRUNCATE TABLE {TARGET}")
                    print("TARGET_TRUNCATE_COMPLETE", flush=True)
                copied_rows = copy_source_to_target(source_cursor, target_cursor, start, end)
                require_reconciliation(target_cursor, expected, start, end, copied_rows)
                target.commit()
                source.rollback()
                print("TARGET_COMMIT_PASS", flush=True)
        except Exception:
            target.rollback()
            source.rollback()
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="perform approved initial DDL and COPY")
    parser.add_argument("--rebuild", action="store_true", help="perform approved atomic rebuild only")
    args = parser.parse_args()
    if args.apply == args.rebuild:
        parser.error("choose exactly one of --apply or --rebuild")
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    print(f"BR003_HORIZON start={start} end={end}", flush=True)
    load("apply" if args.apply else "rebuild", start, end)


if __name__ == "__main__":
    main()
