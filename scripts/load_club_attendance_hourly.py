#!/usr/bin/env python3
"""Atomically load the approved source-side hourly club-attendance aggregate."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.mart_connection import connect_with_retry


DDL = ROOT / "sql/marts/club_attendance_hourly_ddl.sql"
EXTRACT = ROOT / "sql/marts/club_attendance_hourly_extract.sql"
RECONCILIATION = ROOT / "sql/tests/club_attendance_hourly_reconciliation.sql"
TARGET = "mart.club_attendance_hourly"
COLUMNS = "visit_date, club_id, start_hour, end_hour, sex_code, age_years, visit_count, club_minutes_total"


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
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date(today.year + 1, 1, 1)


def sections() -> dict[str, str]:
    parts = re.split(r"(?m)^-- name: ([a-z_]+)\n", EXTRACT.read_text(encoding="utf-8"))
    result = {parts[index]: parts[index + 1].strip().rstrip(";") for index in range(1, len(parts), 2)}
    if set(result) != {"hourly"}:
        raise RuntimeError(f"Unexpected source query names: {sorted(result)}")
    return result


def render(query: str, start: date, end: date) -> str:
    return (query.replace("$1::timestamp without time zone", f"TIMESTAMP '{start}'")
                 .replace("$2::timestamp without time zone", f"TIMESTAMP '{end}'"))


def ddl_without_transaction() -> str:
    text = DDL.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^BEGIN;\s*", "", text, count=1)
    text = re.sub(r"(?m)^COMMIT;\s*$", "", text, count=1)
    if "CREATE TABLE mart.club_attendance_hourly" not in text:
        raise RuntimeError("Unexpected reviewed DDL")
    return text


def month_windows(start: date, end: date):
    current = start
    while current < end:
        next_month = date(current.year + (current.month == 12), (current.month % 12) + 1, 1)
        yield current, min(next_month, end)
        current = next_month


def source_month_controls(source_cursor, query: str) -> tuple:
    source_cursor.execute(
        "SELECT count(*)::bigint, coalesce(sum(visit_count), 0)::bigint, "
        "round(coalesce(sum(club_minutes_total), 0)::numeric, 6), "
        "min(visit_date), max(visit_date) FROM (" + query + ") AS hourly"
    )
    controls = source_cursor.fetchone()
    if controls is None:
        raise RuntimeError("Missing monthly source controls")
    return controls


def copy_source_month(source_cursor, query: str, path: Path) -> int:
    with path.open("wb") as output, source_cursor.copy(
        f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)"
    ) as copy:
        while block := copy.read():
            output.write(block)
    return source_cursor.rowcount


def copy_target_month(target_cursor, path: Path, expected_rows: int) -> None:
    with target_cursor.copy(f"COPY {TARGET} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copy:
        with path.open("rb") as source:
            while block := source.read(1_048_576):
                copy.write(block)
    if target_cursor.rowcount != expected_rows:
        raise RuntimeError(f"Target COPY total differs: {target_cursor.rowcount} != {expected_rows}")


def copy_source_to_target(source_cursor, target_cursor, start: date, end: date) -> tuple[int, tuple]:
    """Copy one month at a time through bounded binary files.

    psycopg stalls after a very large result portal while a second remote COPY
    is open. Each month therefore has its own completed source portal and a
    short-lived local file; both VM transactions remain open until all source
    controls and target reconciliation pass.
    """
    source_cursor.execute("SET LOCAL enable_hashjoin = off")
    aggregate_rows = source_visits = 0
    source_minutes = Decimal("0")
    min_visit_date = max_visit_date = None
    with tempfile.TemporaryDirectory(prefix="club_attendance_hourly_") as directory:
        directory_path = Path(directory)
        for batch_start, batch_end in month_windows(start, end):
            query = render(sections()["hourly"], batch_start, batch_end)
            controls = source_month_controls(source_cursor, query)
            if controls[0] == 0:
                print(
                    f"SOURCE_MONTH_EMPTY start={batch_start} end={batch_end}",
                    flush=True,
                )
                continue
            path = directory_path / f"{batch_start.isoformat()}.copy"
            source_rows = copy_source_month(source_cursor, query, path)
            if source_rows != controls[0]:
                raise RuntimeError(f"Source COPY total differs: {source_rows} != {controls[0]}")
            copy_target_month(target_cursor, path, source_rows)
            aggregate_rows += controls[0]
            source_visits += controls[1]
            source_minutes += controls[2]
            min_visit_date = controls[3] if min_visit_date is None or controls[3] < min_visit_date else min_visit_date
            max_visit_date = controls[4] if max_visit_date is None or controls[4] > max_visit_date else max_visit_date
            print(
                f"SOURCE_MONTH_COPY_COMPLETE start={batch_start} end={batch_end} rows={source_rows} bytes={path.stat().st_size}",
                flush=True,
            )
    controls = (source_visits, round(source_minutes, 6), min_visit_date, max_visit_date)
    if aggregate_rows <= 0:
        raise RuntimeError(f"Source controls failed: aggregate_rows={aggregate_rows} controls={controls}")
    print(
        f"SOURCE_STREAM_COMPLETE rows={aggregate_rows} visits={controls[0]} minutes={controls[1]} "
        f"min_date={controls[2]} max_date={controls[3]}",
        flush=True,
    )
    return aggregate_rows, controls


def relation_exists(cursor) -> bool:
    cursor.execute("SELECT to_regclass('mart.club_attendance_hourly') IS NOT NULL")
    return cursor.fetchone()[0]


def reconciliation_statements(expected_rows: int, controls: tuple, start: date, end: date) -> list[str]:
    text = RECONCILIATION.read_text(encoding="utf-8")
    text = (text.replace("$1::bigint", str(expected_rows)).replace("$2::bigint", str(controls[0]))
                 .replace("$3::numeric", str(controls[1])).replace("$4::date", f"DATE '{start}'")
                 .replace("$5::date", f"DATE '{end}'"))
    return [part.strip().rstrip(";") for part in re.split(r"(?m)(?=-- WA-R\d+)", text)
            if part.strip().startswith("-- WA-R")]


def require_reconciliation(cursor, expected_rows: int, controls: tuple, start: date, end: date) -> None:
    statements = reconciliation_statements(expected_rows, controls, start, end)
    if len(statements) != 6:
        raise RuntimeError(f"Unexpected reconciliation statement count: {len(statements)}")
    rows: list[tuple] = []
    for index, statement in enumerate(statements, 1):
        cursor.execute(statement)
        rows.append(cursor.fetchone())
        print(f"RECONCILIATION_CONTROL_DONE id=WA-R{index:02d}", flush=True)
    if not rows[0][-1] or rows[1][0] != 0 or any(rows[2]) or rows[3][0] != 0 or rows[4][0] != 0 or rows[5][0] != 0:
        raise RuntimeError(f"Reconciliation failed: {rows}")
    print("RECONCILIATION_PASS WA-R01—WA-R06", flush=True)


def load(mode: str, start: date, end: date) -> None:
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        try:
            with source.cursor() as source_cursor, target.cursor() as cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                cursor.execute("BEGIN")
                print("TARGET_TRANSACTION_STARTED", flush=True)
                exists = relation_exists(cursor)
                if mode == "apply":
                    if exists:
                        raise RuntimeError(f"Initial DDL requires absent target: {TARGET}")
                    cursor.execute(ddl_without_transaction())
                    print("TARGET_DDL_READY", flush=True)
                elif not exists:
                    raise RuntimeError(f"Rebuild requires existing target: {TARGET}")
                else:
                    cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.club_attendance_hourly:refresh",))
                    cursor.execute("TRUNCATE TABLE mart.club_attendance_hourly")
                    print("TARGET_TRUNCATE_COMPLETE", flush=True)
                expected_rows, controls = copy_source_to_target(source_cursor, cursor, start, end)
                print(f"TARGET_COPY_READY rows={expected_rows}", flush=True)
                require_reconciliation(cursor, expected_rows, controls, start, end)
                print("TARGET_COMMIT_STARTED", flush=True)
                target.commit()
                print("TARGET_COMMIT_PASS", flush=True)
                source.rollback()
        except Exception:
            target.rollback()
            source.rollback()
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="perform approved initial DDL and DML")
    parser.add_argument("--rebuild", action="store_true", help="perform approved atomic rebuild only")
    args = parser.parse_args()
    if args.apply == args.rebuild:
        parser.error("choose exactly one of --apply or --rebuild")
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    print(f"BR003_HORIZON start={start} end={end}", flush=True)
    load("apply" if args.apply else "rebuild", start, end)


if __name__ == "__main__":
    main()
