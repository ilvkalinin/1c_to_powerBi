#!/usr/bin/env python3
"""Atomically create or rebuild the approved second-month newcomer mart."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path
from time import perf_counter
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.mart_connection import connect_with_retry


EXTRACT = ROOT / "sql/marts/newcomer_engagement_second_month_extract.sql"
DDL = ROOT / "sql/marts/newcomer_engagement_second_month_ddl.sql"
TARGET = "mart.newcomer_engagement_second_month"
COLUMNS = (
    "source_row_id, contract_id, contract_code, client_id, client_code, client_name, "
    "access_club_id, access_club_name, membership_start_date, month_of_engagement, "
    "age_category, tenure, second_month_visit_count, last_visit_date, visit_bucket, "
    "intro_training_status"
)


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"],
        "dbname": values["PGDATABASE"], "user": values["PGUSER"],
        "password": values["PGPASSWORD"], "connect_timeout": "15",
    }
    if sslmode := os.environ.get(prefix + "PGSSLMODE"):
        result["sslmode"] = sslmode
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date.fromordinal(today.toordinal() + 1)


def rendered_extract(start: date, end: date) -> str:
    sql = EXTRACT.read_text(encoding="utf-8").strip().rstrip(";")
    return sql.replace("$1::date", f"DATE '{start}'").replace("$2::date", f"DATE '{end}'")


def ddl_without_transaction() -> str:
    sql = DDL.read_text(encoding="utf-8")
    sql = sql.removeprefix("BEGIN;\n").removesuffix("COMMIT;\n")
    if "CREATE TABLE mart.newcomer_engagement_second_month" not in sql:
        raise RuntimeError("Unexpected reviewed DDL")
    return sql


def month_batches(start: date, end: date) -> list[tuple[date, date]]:
    batches: list[tuple[date, date]] = []
    cursor = start
    while cursor < end:
        next_month = date(cursor.year + (cursor.month == 12), cursor.month % 12 + 1, 1)
        batches.append((cursor, min(next_month, end)))
        cursor = next_month
    return batches


def copy_source_batch(source: psycopg.Connection, start: date, end: date, path: Path) -> int:
    query = rendered_extract(start, end)
    started = perf_counter()
    with source.cursor() as cursor:
        with path.open("wb") as output, cursor.copy(
            f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)"
        ) as copy:
            while block := copy.read():
                output.write(block)
        rows = cursor.rowcount
    print(
        f"SOURCE_COPY_PASS start={start} end={end} rows={rows} bytes={path.stat().st_size} "
        f"elapsed_seconds={perf_counter() - started:.1f}",
        flush=True,
    )
    return rows


def source_expected_controls(source: psycopg.Connection, start: date, end: date) -> tuple[int, int, int, date, date]:
    """Obtain compact expected values in the same source snapshot as transport."""
    query = rendered_extract(start, end)
    with source.cursor() as cursor:
        cursor.execute(
            "SELECT count(*)::bigint, count(DISTINCT (contract_id, client_id, month_of_engagement))::bigint, "
            "coalesce(sum(second_month_visit_count), 0)::bigint, min(month_of_engagement), max(month_of_engagement) "
            f"FROM ({query}) expected"
        )
        controls = cursor.fetchone()
    print(
        "SOURCE_EXPECTED_PASS "
        f"rows={controls[0]} business_pairs={controls[1]} visit_rows={controls[2]} "
        f"min_month={controls[3]} max_month={controls[4]}",
        flush=True,
    )
    return controls


def load(rebuild: bool, start: date, end: date, directory: Path) -> None:
    started = perf_counter()
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        try:
            with source.cursor() as source_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute("SELECT to_regclass(%s) IS NOT NULL", (TARGET,))
                exists = cursor.fetchone()[0]
                if not exists:
                    if rebuild:
                        raise RuntimeError("Rebuild requested but target table is absent")
                    cursor.execute(ddl_without_transaction())
                    print("TARGET_DDL_READY", flush=True)
                elif not rebuild:
                    raise RuntimeError("Target table already exists; use --rebuild")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET,))
                cursor.execute(f"CREATE TEMP TABLE _ne2_stage (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP")
                expected_rows = 0
                for batch_start, batch_end in month_batches(start, end):
                    path = directory / f"{batch_start:%Y%m}.copy"
                    batch_rows = copy_source_batch(source, batch_start, batch_end, path)
                    with cursor.copy(f"COPY _ne2_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copy:
                        with path.open("rb") as copied_source:
                            while block := copied_source.read(1_048_576):
                                copy.write(block)
                    if cursor.rowcount != batch_rows:
                        raise RuntimeError(f"Target batch COPY differs: {cursor.rowcount} != {batch_rows}")
                    expected_rows += batch_rows
                    print(
                        f"TARGET_BATCH_STAGE_PASS start={batch_start} end={batch_end} rows={batch_rows}",
                        flush=True,
                    )
                    path.unlink()
                expected = source_expected_controls(source, start, end)
                cursor.execute(
                    "SELECT count(*)::bigint, count(DISTINCT source_row_id)::bigint, "
                    "count(DISTINCT (contract_id, client_id, month_of_engagement))::bigint, "
                    "coalesce(sum(second_month_visit_count), 0)::bigint, "
                    "min(month_of_engagement), max(month_of_engagement), "
                    "count(*) FILTER (WHERE source_row_id IS NULL OR contract_id IS NULL OR client_id IS NULL "
                    "OR membership_start_date IS NULL OR month_of_engagement IS NULL OR visit_bucket IS NULL "
                    "OR intro_training_status IS NULL)::bigint, "
                    "count(*) FILTER (WHERE month_of_engagement < %s OR month_of_engagement >= %s)::bigint "
                    "FROM _ne2_stage",
                    (start, end),
                )
                rows, identities, business_pairs, visit_rows, min_month, max_month, nulls, outside = cursor.fetchone()
                if (rows, identities, nulls, outside) != (expected_rows, expected_rows, 0, 0):
                    raise RuntimeError(
                        f"Stage control failed rows={rows} identities={identities} nulls={nulls} outside={outside}"
                    )
                if (rows, business_pairs, visit_rows, min_month, max_month) != expected:
                    raise RuntimeError(
                        "Source-to-stage reconciliation failed: "
                        f"expected={expected} actual={(rows, business_pairs, visit_rows, min_month, max_month)}"
                    )
                print(
                    f"TARGET_STAGE_PASS rows={rows} source_identities={identities} "
                    f"business_pairs={business_pairs} visit_rows={visit_rows}",
                    flush=True,
                )
                if exists:
                    cursor.execute(f"LOCK TABLE {TARGET} IN ACCESS EXCLUSIVE MODE")
                    cursor.execute(f"DELETE FROM {TARGET}")
                cursor.execute(f"INSERT INTO {TARGET} ({COLUMNS}) SELECT {COLUMNS} FROM _ne2_stage")
                if cursor.rowcount != expected_rows:
                    raise RuntimeError(f"Target insert differs: {cursor.rowcount} != {expected_rows}")
                cursor.execute(f"SELECT count(*)::bigint FROM {TARGET}")
                if cursor.fetchone()[0] != expected_rows:
                    raise RuntimeError("Target total differs after insert")
                target.commit()
                source.rollback()
                print(
                    f"TARGET_COMMIT_PASS rows={expected_rows} elapsed_seconds={perf_counter() - started:.1f}",
                    flush=True,
                )
        except Exception:
            target.rollback()
            source.rollback()
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="create and initially load an absent table")
    mode.add_argument("--rebuild", action="store_true", help="atomically replace an existing table")
    args = parser.parse_args()
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    print(f"BR003_HORIZON start={start} end={end}", flush=True)
    with tempfile.TemporaryDirectory(prefix="newcomer_engagement_second_month_") as directory:
        load(args.rebuild, start, end, Path(directory))


if __name__ == "__main__":
    main()
