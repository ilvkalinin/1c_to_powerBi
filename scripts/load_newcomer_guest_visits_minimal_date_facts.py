#!/usr/bin/env python3
"""Atomically load the approved minimal date facts for newcomer and guest visits."""

from __future__ import annotations

import argparse
import os
import re
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

EXTRACT = ROOT / "sql/marts/newcomer_guest_visits_minimal_date_facts_extract.sql"
DDL = ROOT / "sql/marts/newcomer_guest_visits_minimal_date_facts_ddl.sql"
RECONCILIATION = ROOT / "sql/tests/newcomer_guest_visits_minimal_date_facts_reconciliation.sql"
TARGETS = {
    "first_visit": "mart.new_first_visit",
    "guest_visit_conversion": "mart.guest_visit_conversion",
}
COLUMNS = {
    "first_visit": "contract_id, first_visit_date",
    "guest_visit_conversion": (
        "client_id, client_code, guest_visit_date, accuniq_same_day_flag, "
        "purchase_activation_date, purchase_lag_days"
    ),
}


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result = {
        "host": values["PGHOST"],
        "port": values["PGPORT"],
        "dbname": values["PGDATABASE"],
        "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
        "connect_timeout": "15",
    }
    if sslmode := os.environ.get(prefix + "PGSSLMODE"):
        result["sslmode"] = sslmode
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date(today.year + 1, 1, 1)


def sections() -> dict[str, str]:
    parts = re.split(r"(?m)^-- name: ([a-z_]+)\n", EXTRACT.read_text(encoding="utf-8"))
    result = {parts[index]: parts[index + 1].strip().rstrip(";") for index in range(1, len(parts), 2)}
    if set(result) != set(TARGETS):
        raise RuntimeError(f"Unexpected source query names: {sorted(result)}")
    return result


def render_extract(query: str, start: date, end: date) -> str:
    return (query.replace("$1::timestamp without time zone", f"TIMESTAMP '{start}'")
            .replace("$2::timestamp without time zone", f"TIMESTAMP '{end}'"))


def ddl_without_transaction() -> str:
    text = DDL.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^BEGIN;\s*", "", text, count=1)
    text = re.sub(r"(?m)^COMMIT;\s*$", "", text, count=1)
    if "CREATE TABLE mart.new_first_visit" not in text or "CREATE TABLE mart.guest_visit_conversion" not in text:
        raise RuntimeError("Unexpected reviewed DDL")
    return text


def source_controls(cursor, query_parts: dict[str, str], start: date, end: date,
                    counts: dict[str, int]) -> None:
    values: dict[str, tuple] = {}
    for name in ("first_visit", "guest_visit_conversion"):
        cursor.execute(
            "SELECT count(*)::bigint, min(event_date), max(event_date), "
            "count(*) FILTER (WHERE stable_key IS NULL OR btrim(stable_key) = '')::bigint "
            f"FROM (SELECT {'contract_id AS stable_key, first_visit_date AS event_date' if name == 'first_visit' else 'client_id AS stable_key, guest_visit_date AS event_date'} "
            f"FROM ({render_extract(query_parts[name], start, end)}) AS extracted) AS control"
        )
        values[name] = cursor.fetchone()
        if values[name][0] != counts[name] or values[name][3] != 0:
            raise RuntimeError(f"Source control failed for {name}: rows={values[name][0]} copy={counts[name]} invalid_key={values[name][3]}")
        print(
            f"SOURCE_CONTROL_PASS name={name} rows={values[name][0]} "
            f"min_date={values[name][1]} max_date={values[name][2]}",
            flush=True,
        )


def copy_source(start: date, end: date, directory: Path) -> tuple[dict[str, Path], dict[str, int]]:
    paths: dict[str, Path] = {}
    counts: dict[str, int] = {}
    query_parts = sections()
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            for ordinal, name in enumerate(("first_visit", "guest_visit_conversion"), 1):
                path = directory / f"{ordinal:02d}_{name}.copy"
                with path.open("wb") as output, cursor.copy(
                    f"COPY ({render_extract(query_parts[name], start, end)}) TO STDOUT WITH (FORMAT BINARY)"
                ) as copy:
                    while block := copy.read():
                        output.write(block)
                paths[name], counts[name] = path, cursor.rowcount
                print(f"SOURCE_COPY_READY name={name} rows={cursor.rowcount}", flush=True)
            source_controls(cursor, query_parts, start, end, counts)
            source.rollback()
    return paths, counts


def relation_names(cursor) -> set[str]:
    cursor.execute(
        """SELECT c.relname FROM pg_class AS c
           JOIN pg_namespace AS n ON n.oid = c.relnamespace
           WHERE n.nspname = 'mart'
             AND c.relname IN ('new_first_visit', 'guest_visit_conversion')"""
    )
    return {row[0] for row in cursor}


def copy_target(cursor, name: str, path: Path, expected: int) -> None:
    with cursor.copy(f"COPY {TARGETS[name]} ({COLUMNS[name]}) FROM STDIN WITH (FORMAT BINARY)") as copy:
        with path.open("rb") as source:
            while block := source.read(1_048_576):
                copy.write(block)
    if cursor.rowcount != expected:
        raise RuntimeError(f"COPY total differs for {name}: {cursor.rowcount} != {expected}")
    print(f"TARGET_COPY_READY name={name} rows={cursor.rowcount} bytes={path.stat().st_size}", flush=True)


def reconciliation_statements(first_rows: int, guest_rows: int, start: date, end: date) -> list[str]:
    text = RECONCILIATION.read_text(encoding="utf-8")
    text = (text.replace("$1::bigint", str(first_rows)).replace("$2::bigint", str(guest_rows))
            .replace("$3::date", f"DATE '{start}'").replace("$4::date", f"DATE '{end}'"))
    return [part.strip().rstrip(";")
            for part in re.split(r"(?m)(?=-- NV-R\d+)", text)
            if part.strip().startswith("-- NV-R")]


def require_reconciliation(cursor, counts: dict[str, int], start: date, end: date) -> None:
    statements = reconciliation_statements(counts["first_visit"], counts["guest_visit_conversion"], start, end)
    if len(statements) != 6:
        raise RuntimeError(f"Unexpected reconciliation statement count: {len(statements)}")
    rows = []
    for ordinal, statement in enumerate(statements, 1):
        cursor.execute(statement)
        row = cursor.fetchone()
        rows.append(row)
        print(f"RECONCILIATION_CONTROL_DONE id=NV-R{ordinal:02d}", flush=True)
    if not rows[0][-1] or any(rows[1]) or any(rows[2]) or any(rows[3]) or any(rows[4]) or rows[5][0] != 0:
        raise RuntimeError(f"Reconciliation failed: {rows}")
    print("RECONCILIATION_PASS NV-R01—NV-R06", flush=True)


def load(mode: str, paths: dict[str, Path], counts: dict[str, int], start: date, end: date) -> None:
    expected = {"new_first_visit", "guest_visit_conversion"}
    with connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                print("TARGET_TRANSACTION_STARTED", flush=True)
                found = relation_names(cursor)
                if mode == "apply":
                    if found:
                        raise RuntimeError(f"Initial DDL requires absent targets, found: {sorted(found)}")
                    cursor.execute(ddl_without_transaction())
                    print("TARGET_DDL_READY", flush=True)
                elif found != expected:
                    raise RuntimeError(f"Rebuild requires both targets, found: {sorted(found)}")
                else:
                    cursor.execute("LOCK TABLE mart.new_first_visit, mart.guest_visit_conversion IN ACCESS EXCLUSIVE MODE")
                    print("TARGET_LOCK_ACQUIRED", flush=True)
                    cursor.execute("DELETE FROM mart.new_first_visit")
                    cursor.execute("DELETE FROM mart.guest_visit_conversion")
                    print("TARGET_DELETE_COMPLETE", flush=True)
                for name in ("first_visit", "guest_visit_conversion"):
                    copy_target(cursor, name, paths[name], counts[name])
                require_reconciliation(cursor, counts, start, end)
                print("TARGET_COMMIT_STARTED", flush=True)
                target.commit()
                print("TARGET_COMMIT_PASS", flush=True)
        except Exception:
            target.rollback()
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()
    if args.apply == args.rebuild:
        parser.error("choose exactly one of --apply or --rebuild")
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    print(f"BR003_HORIZON start={start} end={end}", flush=True)
    with tempfile.TemporaryDirectory(prefix="newcomer_guest_date_facts_") as directory:
        paths, counts = copy_source(start, end, Path(directory))
        load("apply" if args.apply else "rebuild", paths, counts, start, end)


if __name__ == "__main__":
    main()
