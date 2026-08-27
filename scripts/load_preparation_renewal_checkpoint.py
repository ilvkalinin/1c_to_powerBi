#!/usr/bin/env python3
"""Atomically load the approved preparation-renewal checkpoint mart."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.mart_connection import connect_with_retry


DDL = ROOT / "sql/marts/preparation_renewal_checkpoint_ddl.sql"
EXTRACT = ROOT / "sql/marts/preparation_renewal_checkpoint_extract.sql"
SOURCE_CONTROLS = ROOT / "sql/marts/preparation_renewal_checkpoint_source_controls.sql"
RECONCILIATION = ROOT / "sql/tests/preparation_renewal_checkpoint_reconciliation.sql"
TARGET = "mart.preparation_renewal_checkpoint"
COLUMNS = (
    "contract_id, contract_code, client_id, membership_start_date, membership_end_date, "
    "access_club_id, access_club_name, checkpoint_day, checkpoint_date, "
    "visit_count_to_checkpoint, visit_bucket, target_visit_count, below_target_flag, "
    "frozen_at_checkpoint_flag, age_group, membership_tenure"
)
MIN_FREE_BYTES = 1 << 30


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
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date.fromordinal(today.toordinal() + 1)


def quarter_windows(start: date, end: date):
    current = start
    while current < end:
        month = current.month + 3
        next_start = date(current.year + (month - 1) // 12, (month - 1) % 12 + 1, 1)
        yield current, min(next_start, end)
        current = next_start


def extract_query() -> str:
    text = EXTRACT.read_text(encoding="utf-8")
    prefix = "-- name: checkpoint\n"
    if text.count(prefix) != 1:
        raise RuntimeError("Unexpected reviewed extract sections")
    return text.split(prefix, 1)[1].strip().rstrip(";")


def render(query: str, start: date, end: date) -> str:
    return (query.replace("$1::timestamp without time zone", f"TIMESTAMP '{start}'")
                 .replace("$2::timestamp without time zone", f"TIMESTAMP '{end}'")
                 .replace("$1::date", f"DATE '{start}'")
                 .replace("$2::date", f"DATE '{end}'"))


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


def source_controls(cursor, start: date, end: date) -> tuple[int, int, int, int, date | None, date | None]:
    cursor.execute(render(SOURCE_CONTROLS.read_text(encoding="utf-8").strip().rstrip(";"), start, end))
    values = cursor.fetchone()
    if values is None or values[0] is None:
        raise RuntimeError("Independent source controls returned no result")
    return values


def copy_source_batch(cursor, query: str, path: Path) -> int:
    with path.open("wb") as output, cursor.copy(f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)") as copy:
        while block := copy.read():
            output.write(block)
    return cursor.rowcount


def copy_target_batch(cursor, path: Path, expected_rows: int) -> None:
    with cursor.copy(f"COPY {TARGET} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copy:
        with path.open("rb") as source:
            while block := source.read(1_048_576):
                copy.write(block)
    if cursor.rowcount != expected_rows:
        raise RuntimeError(f"Target COPY row count differs: {cursor.rowcount} != {expected_rows}")


def reconciliation_statements(expected: tuple[int, int, int, int], start: date, end: date) -> list[str]:
    text = RECONCILIATION.read_text(encoding="utf-8")
    values = (*expected, start, end)
    for index, value in enumerate(values, 1):
        token = f"${index}::{'date' if index >= 5 else 'bigint'}"
        replacement = f"DATE '{value}'" if index >= 5 else str(value)
        text = text.replace(token, replacement)
    return [part.strip().rstrip(";") for part in re.split(r"(?m)(?=-- PR-R\d+)", text)
            if part.strip().startswith("-- PR-R")]


def require_reconciliation(cursor, expected: tuple[int, int, int, int], start: date, end: date) -> None:
    statements = reconciliation_statements(expected, start, end)
    if len(statements) != 6:
        raise RuntimeError(f"Unexpected reconciliation statement count: {len(statements)}")
    rows: list[tuple] = []
    for ordinal, statement in enumerate(statements, 1):
        cursor.execute(statement)
        rows.append(cursor.fetchone())
        print(f"RECONCILIATION_CONTROL_DONE id=PR-R{ordinal:02d}", flush=True)
    if not rows[0][-1] or rows[1][0] != 0 or any(rows[2]) or any(rows[3]) or rows[4][0] != 0 or rows[5][0] != 0:
        raise RuntimeError(f"Reconciliation failed: {rows}")
    print("RECONCILIATION_PASS PR-R01—PR-R06", flush=True)


def load(mode: str, start: date, end: date) -> None:
    source_query = extract_query()
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        try:
            with source.cursor() as source_cursor, target.cursor() as target_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                source_cursor.execute("SET LOCAL statement_timeout = '60s'")
                target_cursor.execute("BEGIN")
                print("TARGET_TRANSACTION_STARTED", flush=True)
                exists = relation_exists(target_cursor)
                if mode == "apply":
                    if exists:
                        raise RuntimeError(f"Initial DDL requires absent target: {TARGET}")
                    target_cursor.execute(ddl_without_transaction())
                    print("TARGET_DDL_READY", flush=True)
                elif not exists:
                    raise RuntimeError(f"Rebuild requires existing target: {TARGET}")
                else:
                    target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET + ":refresh",))
                    target_cursor.execute(f"TRUNCATE TABLE {TARGET}")
                    print("TARGET_TRUNCATE_COMPLETE", flush=True)

                totals = [0, 0, 0, 0]
                with tempfile.TemporaryDirectory(prefix="preparation_renewal_checkpoint_") as directory:
                    directory_path = Path(directory)
                    for batch_start, batch_end in quarter_windows(start, end):
                        free_bytes = shutil.disk_usage(directory_path).free
                        if free_bytes < MIN_FREE_BYTES:
                            raise RuntimeError(f"Insufficient temporary transport space: {free_bytes} bytes")
                        expected = source_controls(source_cursor, batch_start, batch_end)
                        path = directory_path / f"{batch_start.isoformat()}.copy"
                        source_rows = copy_source_batch(source_cursor, render(source_query, batch_start, batch_end), path)
                        if source_rows != expected[0]:
                            raise RuntimeError(f"Independent source rows differ from COPY: {source_rows} != {expected[0]}")
                        if source_rows:
                            copy_target_batch(target_cursor, path, source_rows)
                        size = path.stat().st_size
                        path.unlink()
                        for index in range(4):
                            totals[index] += expected[index]
                        print(
                            f"SOURCE_BATCH_COMPLETE start={batch_start} end={batch_end} rows={source_rows} "
                            f"bytes={size} free_before={free_bytes}",
                            flush=True,
                        )
                expected_totals = tuple(totals)
                require_reconciliation(target_cursor, expected_totals, start, end)
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
    parser.add_argument("--apply", action="store_true", help="perform approved initial DDL and load")
    parser.add_argument("--rebuild", action="store_true", help="perform approved atomic full rebuild")
    args = parser.parse_args()
    if args.apply == args.rebuild:
        parser.error("choose exactly one of --apply or --rebuild")
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    print(f"BR003_HORIZON start={start} end={end}", flush=True)
    load("apply" if args.apply else "rebuild", start, end)


if __name__ == "__main__":
    main()
