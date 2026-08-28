#!/usr/bin/env python3
"""Atomically deliver mart.contract_usage only after physical admission.

The runner derives the mandatory BR-003 Moscow horizon, so future visit facts
cannot enter the target. Technical review never invokes it.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

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
    "usage_rate,average_monthly_visits"
)
CONNECTION_OPTIONS = {
    "connect_timeout": 15,
    "keepalives": 1,
    "keepalives_idle": 60,
    "keepalives_interval": 15,
    "keepalives_count": 4,
    "tcp_user_timeout": 180_000,
}
SOURCE_SNAPSHOT_ATTEMPTS = 3


def br003_horizon(today: date) -> tuple[date, date]:
    """Return the confirmed inclusive/exclusive fact horizon without future dates."""
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date.fromordinal(today.toordinal() + 1)


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


def snapshot_reader(snapshot_id: str, name: str) -> tuple[psycopg.Connection, psycopg.Cursor]:
    """Open a short read-only reader on the anchor's exported source snapshot."""
    if not re.fullmatch(r"[0-9A-Fa-f-]+", snapshot_id):
        raise RuntimeError("source returned an invalid exported snapshot identifier")
    connection = source_connection(name)
    cursor = connection.cursor()
    try:
        cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        cursor.execute(f"SET TRANSACTION SNAPSHOT '{snapshot_id}'")
        cursor.execute("SET LOCAL statement_timeout = '300s'")
    except Exception:
        cursor.close()
        connection.close()
        raise
    return connection, cursor


def independent_expected(start: date, end: date, snapshot_id: str, anchor: psycopg.Cursor) -> dict[str, object]:
    results: dict[str, dict[str, object]] = {}
    for number, statement in enumerate(statements(CONTROLS), start=1):
        reader, cursor = snapshot_reader(snapshot_id, f"contract_usage_source_control_{number}")
        try:
            cursor.execute(render_statement(statement, (start, end)))
            row = cursor.fetchone()
            results[row[0]] = dict(zip((column.name for column in cursor.description), row, strict=True))
            cursor.execute("ROLLBACK")
        finally:
            cursor.close()
            reader.close()
        anchor.execute("SELECT 1")

    key, code, shape, horizon = results["CU-S01"], results["CU-S02"], results["CU-S03"], results["CU-S04"]
    if int(key["duplicate_technical_key_rows"]) != 0:
        raise RuntimeError("CU-S01 failed: duplicate current-M technical visit keys")
    if key["polymorphic_type_pairs"] != "08/0000003b":
        raise RuntimeError(f"CU-S01 failed: unexpected polymorphic type domain {key['polymorphic_type_pairs']!r}")
    if int(code["duplicate_code_groups"]) != 0:
        raise RuntimeError("CU-S02 failed: current Power Query code groups multiple contract IDs")
    if int(horizon["future_visit_rows"]) != 0:
        raise RuntimeError("CU-S04 failed: future visit facts are present beyond the BR-003 horizon")
    for name in (
        "null_membership_date_rows",
        "invalid_membership_interval_rows",
        "nonpositive_active_calendar_month_rows",
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
    start: date, end: date, transfer: Path, max_transfer_bytes: int
) -> tuple[dict[str, object], int]:
    anchor_connection = source_connection("contract_usage_source_snapshot_anchor")
    try:
        with anchor_connection.cursor() as anchor:
            anchor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            anchor.execute("SELECT pg_export_snapshot()")
            snapshot_id = anchor.fetchone()[0]
            expected = independent_expected(start, end, snapshot_id, anchor)
            source, cursor = snapshot_reader(snapshot_id, "contract_usage_source_copy")
            try:
                with transfer.open("wb") as output:
                    with cursor.copy(
                        "COPY (" + render(EXTRACT, (start, end)) + ") TO STDOUT WITH (FORMAT BINARY)"
                    ) as copied:
                        for block in copied:
                            output.write(block)
                            if output.tell() > max_transfer_bytes:
                                raise RuntimeError("derived transfer exceeded its explicitly approved byte cap")
                    cursor.execute("ROLLBACK")
            finally:
                cursor.close()
                source.close()
            anchor.execute("ROLLBACK")
            return expected, transfer.stat().st_size
    finally:
        anchor_connection.close()


def copy_source_with_snapshot_retries(
    start: date, end: date, transfer: Path, max_transfer_bytes: int
) -> tuple[dict[str, object], int]:
    """Restart all source work in a fresh snapshot after an in-statement VPN failure."""
    for attempt in range(1, SOURCE_SNAPSHOT_ATTEMPTS + 1):
        try:
            return copy_source_to_file(start, end, transfer, max_transfer_bytes)
        except psycopg.OperationalError as error:
            transfer.unlink(missing_ok=True)
            if attempt == SOURCE_SNAPSHOT_ATTEMPTS:
                raise RuntimeError(
                    f"source snapshot failed after {SOURCE_SNAPSHOT_ATTEMPTS} complete attempts"
                ) from error
            print(
                f"SOURCE_SNAPSHOT_RETRY attempt={attempt + 1}/{SOURCE_SNAPSHOT_ATTEMPTS} "
                "reason=operational_error",
                flush=True,
            )


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
    """Atomically replace the full target after all source work has completed."""
    if not initial:
        cursor.execute(f"DELETE FROM {TABLE}")
    cursor.execute(f"INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM _contract_usage_stage")


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
    horizon_start, horizon_end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    if shutil.disk_usage(arguments.transfer_dir).free < arguments.max_transfer_bytes:
        raise RuntimeError("insufficient free space for the explicitly capped derived transfer file")
    with tempfile.TemporaryDirectory(prefix="contract_usage_", dir=arguments.transfer_dir) as folder:
        transfer = Path(folder) / "contract_usage.copy"
        expected, transfer_bytes = copy_source_with_snapshot_retries(
            horizon_start,
            horizon_end,
            transfer,
            arguments.max_transfer_bytes,
        )
        print(
            "SOURCE_CONTROLS_PASS "
            f"horizon={horizon_start}..{horizon_end} "
            f"target_grain_rows={expected['target_grain_rows']} "
            f"visit_count_sum={expected['visit_count_sum']} "
            f"min_membership_start_date={expected['min_membership_start_date']} "
            f"max_membership_end_date={expected['max_membership_end_date']} "
            f"derived_transfer_bytes={transfer_bytes}",
            flush=True,
        )
        if arguments.measure_only:
            print("SOURCE_MEASUREMENT_PASS target_opened=false", flush=True)
            return
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
    parser.add_argument("--max-transfer-bytes", type=int, required=True)
    parser.add_argument("--transfer-dir", type=Path, default=Path("/tmp"))
    parser.add_argument("--initial", action="store_true")
    parser.add_argument(
        "--measure-only",
        action="store_true",
        help="run source controls and derived COPY only; never open the target",
    )
    run(parser.parse_args())


if __name__ == "__main__":
    main()
