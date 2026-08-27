#!/usr/bin/env python3
"""Atomically rebuild the approved newcomer-engagement milestone mart."""

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


EXTRACT = ROOT / "sql/marts/newcomer_engagement_milestone_extract.sql"
DDL = ROOT / "sql/marts/newcomer_engagement_milestone_ddl.sql"
TARGET = "mart.newcomer_engagement_milestone"
COLUMNS = (
    "contract_id, contract_code, client_id, client_code, access_club_id, "
    "access_club_name, membership_start_date, checkpoint_day, checkpoint_date, "
    "visit_count_to_checkpoint, visit_bucket, target_visit_count, below_target_flag, "
    "frozen_at_checkpoint_flag, eligible_flag, age_group"
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
    return (sql.replace("$1::date", f"DATE '{start}'")
               .replace("$2::date", f"DATE '{end}'"))


def ddl_without_transaction() -> str:
    sql = DDL.read_text(encoding="utf-8")
    sql = sql.removeprefix("BEGIN;\n").removesuffix("COMMIT;\n")
    if "CREATE TABLE mart.newcomer_engagement_milestone" not in sql:
        raise RuntimeError("Unexpected reviewed DDL")
    return sql


def copy_source(start: date, end: date, path: Path) -> int:
    query = rendered_extract(start, end)
    started = perf_counter()
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            with path.open("wb") as output, cursor.copy(
                f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)"
            ) as copy:
                while block := copy.read():
                    output.write(block)
            rows = cursor.rowcount
            source.rollback()
    print(
        f"SOURCE_COPY_PASS rows={rows} bytes={path.stat().st_size} elapsed_seconds={perf_counter() - started:.1f}",
        flush=True,
    )
    return rows


def load(rebuild: bool, path: Path, expected_rows: int) -> None:
    started = perf_counter()
    with connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        try:
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
                cursor.execute(f"CREATE TEMP TABLE _ne_stage (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP")
                with cursor.copy(f"COPY _ne_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as copy:
                    with path.open("rb") as source:
                        while block := source.read(1_048_576):
                            copy.write(block)
                if cursor.rowcount != expected_rows:
                    raise RuntimeError(f"Target stage COPY differs: {cursor.rowcount} != {expected_rows}")
                cursor.execute(
                    "SELECT count(*)::bigint, count(DISTINCT (contract_id, client_id, checkpoint_day))::bigint, "
                    "count(*) FILTER (WHERE checkpoint_date <> membership_start_date + checkpoint_day - 1)::bigint, "
                    "count(*) FILTER (WHERE visit_count_to_checkpoint < 0)::bigint "
                    "FROM _ne_stage"
                )
                rows, keys, invalid_date, invalid_visits = cursor.fetchone()
                if (rows, keys, invalid_date, invalid_visits) != (expected_rows, expected_rows, 0, 0):
                    raise RuntimeError(
                        "Stage control failed: "
                        f"rows={rows} keys={keys} invalid_date={invalid_date} invalid_visits={invalid_visits}"
                    )
                print(f"TARGET_STAGE_PASS rows={rows} distinct_keys={keys}", flush=True)
                if exists:
                    cursor.execute(f"LOCK TABLE {TARGET} IN ACCESS EXCLUSIVE MODE")
                    cursor.execute(f"DELETE FROM {TARGET}")
                cursor.execute(f"INSERT INTO {TARGET} ({COLUMNS}) SELECT {COLUMNS} FROM _ne_stage")
                if cursor.rowcount != expected_rows:
                    raise RuntimeError(f"Target insert differs: {cursor.rowcount} != {expected_rows}")
                cursor.execute(f"SELECT count(*)::bigint FROM {TARGET}")
                if cursor.fetchone()[0] != expected_rows:
                    raise RuntimeError("Target total differs after insert")
                target.commit()
                print(f"TARGET_COMMIT_PASS rows={expected_rows} elapsed_seconds={perf_counter() - started:.1f}", flush=True)
        except Exception:
            target.rollback()
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="create and initially load an absent table")
    mode.add_argument("--rebuild", action="store_true", help="atomically replace an existing table")
    args = parser.parse_args()
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    print(f"BR003_HORIZON start={start} end={end}", flush=True)
    with tempfile.TemporaryDirectory(prefix="newcomer_engagement_milestone_") as directory:
        path = Path(directory) / "extract.copy"
        rows = copy_source(start, end, path)
        load(args.rebuild, path, rows)


if __name__ == "__main__":
    main()
