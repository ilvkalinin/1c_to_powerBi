#!/usr/bin/env python3
"""Atomically deliver mart.contract_usage only after physical admission.

This reviewed runner is intentionally parameter-only: it has no default source
window or finalization cutoff.  Technical review never invokes it.
"""
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
from psycopg import sql

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.mart_connection import connect_with_retry
from scripts.load_children_package_sale import config


EXTRACT = ROOT / "sql/marts/contract_usage_source_extract.sql"
CONTROLS = ROOT / "sql/marts/contract_usage_source_controls.sql"
DDL = ROOT / "sql/marts/contract_usage_ddl.sql"
RECONCILIATION = ROOT / "sql/tests/contract_usage_reconciliation.sql"
TABLE = "mart.contract_usage"
COLUMNS = (
    "contract_id,contract_code,membership_start_date,membership_end_date,"
    "contract_end_month,membership_term_days,active_calendar_months,visit_count,"
    "usage_rate,average_monthly_visits,is_finalized,finalized_month"
)
CONNECTION_OPTIONS = {
    "connect_timeout": 15,
    "keepalives": 1,
    "keepalives_idle": 60,
    "keepalives_interval": 15,
    "keepalives_count": 4,
    "tcp_user_timeout": 180_000,
}


def parse_month(value: str) -> date:
    parsed = date.fromisoformat(value)
    if parsed.day != 1:
        raise argparse.ArgumentTypeError("--mutable-from-month must be the first day of a month")
    return parsed


def parse_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def source_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(
        lambda: psycopg.connect(**(config("SOURCE_") | CONNECTION_OPTIONS | {"application_name": name})),
        endpoint="source",
    )


def target_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(
        lambda: psycopg.connect(**(config("MART_") | CONNECTION_OPTIONS | {"application_name": name})),
        endpoint="mart",
    )


def render(path: Path, parameters: tuple[date, ...]) -> str:
    text = path.read_text(encoding="utf-8").strip().rstrip(";")
    for position, value in enumerate(parameters, start=1):
        text = text.replace(f"${position}::date", f"DATE '{value.isoformat()}'")
    return text


def statements(path: Path) -> list[str]:
    body = "\n".join(
        line for line in path.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("--")
    )
    return [statement.strip() for statement in body.split(";") if statement.strip()]


def execute_ddl(cursor: psycopg.Cursor) -> None:
    for statement in statements(DDL):
        cursor.execute(statement)


def independent_expected(cursor: psycopg.Cursor, start: date, end: date) -> dict[str, object]:
    results: dict[str, dict[str, object]] = {}
    for statement in statements(CONTROLS):
        cursor.execute(render_statement(statement, (start, end)))
        row = cursor.fetchone()
        results[row[0]] = dict(zip((column.name for column in cursor.description), row, strict=True))

    key, code, shape = results["CU-S01"], results["CU-S02"], results["CU-S03"]
    if int(key["duplicate_technical_key_rows"]) != 0:
        raise RuntimeError("CU-S01 failed: duplicate current-M technical visit keys")
    if key["polymorphic_type_pairs"] != "08/0000003b":
        raise RuntimeError(f"CU-S01 failed: unexpected polymorphic type domain {key['polymorphic_type_pairs']!r}")
    if int(code["duplicate_code_groups"]) != 0:
        raise RuntimeError("CU-S02 failed: current Power Query code groups multiple contract IDs")
    for name in (
        "null_membership_date_rows",
        "reversed_membership_interval_rows",
        "null_term_rows",
        "negative_term_rows",
        "nonpositive_visit_count_rows",
    ):
        if int(shape[name]) != 0:
            raise RuntimeError(f"CU-S03 failed: {name}={shape[name]}")
    return shape


def render_statement(statement: str, parameters: tuple[date, ...]) -> str:
    for position, value in enumerate(parameters, start=1):
        statement = statement.replace(f"${position}::date", f"DATE '{value.isoformat()}'")
    return statement


def copy_source_to_file(
    start: date, end: date, mutable_from_month: date, transfer: Path, max_transfer_bytes: int
) -> dict[str, object]:
    source = source_connection("contract_usage_source_copy")
    try:
        with source.cursor() as cursor, transfer.open("wb") as output:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout = '300s'")
            expected = independent_expected(cursor, start, end)
            with cursor.copy(
                "COPY (" + render(EXTRACT, (start, end, mutable_from_month)) + ") TO STDOUT WITH (FORMAT BINARY)"
            ) as copied:
                for block in copied:
                    output.write(block)
                    if output.tell() > max_transfer_bytes:
                        raise RuntimeError("derived transfer exceeded its explicitly approved byte cap")
            cursor.execute("ROLLBACK")
            return expected
    finally:
        source.close()


def copy_file_to_stage(cursor: psycopg.Cursor, transfer: Path) -> None:
    with transfer.open("rb") as input_file, cursor.copy(
        f"COPY _contract_usage_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
    ) as copied:
        while block := input_file.read(1_048_576):
            copied.write(block)


def prepare_target_stage(cursor: psycopg.Cursor, initial: bool) -> None:
    if initial:
        execute_ddl(cursor)
    cursor.execute("CREATE TEMP TABLE _contract_usage_stage (LIKE mart.contract_usage INCLUDING ALL) ON COMMIT DROP")


def apply_stage(cursor: psycopg.Cursor, initial: bool) -> None:
    """Apply a populated stage after all source work has completed."""
    if not initial:
        cursor.execute(
            """UPDATE mart.contract_usage AS target
                  SET contract_code = stage.contract_code,
                      membership_start_date = stage.membership_start_date,
                      membership_end_date = stage.membership_end_date,
                      contract_end_month = stage.contract_end_month,
                      membership_term_days = stage.membership_term_days,
                      active_calendar_months = stage.active_calendar_months,
                      visit_count = stage.visit_count,
                      usage_rate = stage.usage_rate,
                      average_monthly_visits = stage.average_monthly_visits,
                      is_finalized = TRUE,
                      finalized_month = stage.finalized_month
                 FROM _contract_usage_stage AS stage
                WHERE target.contract_id = stage.contract_id
                  AND NOT target.is_finalized
                  AND stage.is_finalized"""
        )
        cursor.execute(
            f"""INSERT INTO {TABLE} ({COLUMNS})
                SELECT {COLUMNS} FROM _contract_usage_stage AS stage
                 WHERE stage.is_finalized
                   AND NOT EXISTS (
                       SELECT 1 FROM {TABLE} AS target WHERE target.contract_id = stage.contract_id
                   )"""
        )
        cursor.execute(f"DELETE FROM {TABLE} WHERE NOT is_finalized")
    if initial:
        cursor.execute(f"INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM _contract_usage_stage")
    else:
        cursor.execute(
            f"INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM _contract_usage_stage WHERE NOT is_finalized"
        )


def reconcile(cursor: psycopg.Cursor, expected: dict[str, object]) -> None:
    body = "\n".join(
        line for line in RECONCILIATION.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("--")
    )
    values = (
        expected["target_grain_rows"],
        expected["visit_count_sum"],
        expected["min_membership_start_date"],
        expected["max_membership_end_date"],
    )
    arguments = tuple(values[int(match.group(1)) - 1] for match in re.finditer(r"\$(\d+)", body))
    cursor.execute(re.sub(r"\$\d+", "%s", body), arguments)
    failed = [row[:3] for row in cursor.fetchall() if row[4] != "PASS"]
    if failed:
        raise RuntimeError(f"target reconciliation failed: {failed}")


def run(arguments: argparse.Namespace) -> None:
    if arguments.legacy_end <= arguments.legacy_start:
        raise RuntimeError("legacy window end must be after start")
    if shutil.disk_usage(arguments.transfer_dir).free < arguments.max_transfer_bytes:
        raise RuntimeError("insufficient free space for the explicitly capped derived transfer file")
    with tempfile.TemporaryDirectory(prefix="contract_usage_", dir=arguments.transfer_dir) as folder:
        transfer = Path(folder) / "contract_usage.copy"
        expected = copy_source_to_file(
            arguments.legacy_start,
            arguments.legacy_end,
            arguments.mutable_from_month,
            transfer,
            arguments.max_transfer_bytes,
        )
        target = target_connection("contract_usage_atomic_delivery")
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext('mart.contract_usage'))")
                prepare_target_stage(cursor, arguments.initial)
                copy_file_to_stage(cursor, transfer)
                apply_stage(cursor, arguments.initial)
                reconcile(cursor, expected)
                cursor.execute("COMMIT")
        except Exception:
            target.rollback()
            raise
        finally:
            target.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--legacy-start", type=parse_date, required=True)
    parser.add_argument("--legacy-end", type=parse_date, required=True)
    parser.add_argument("--mutable-from-month", type=parse_month, required=True)
    parser.add_argument("--max-transfer-bytes", type=int, required=True)
    parser.add_argument("--transfer-dir", type=Path, default=Path("/tmp"))
    parser.add_argument("--initial", action="store_true")
    run(parser.parse_args())


if __name__ == "__main__":
    main()
