#!/usr/bin/env python3
"""Atomically rebuild mart.ip_training_daily from one 1C source snapshot."""

from __future__ import annotations

import argparse
import os
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/ip_training_daily_extract.sql"
COLUMNS = """
training_date, club_id, employee_id, employee_name, client_key,
client_code, service_id, service_name, training_count
""".replace("\n", " ")


def config(prefix: str) -> dict[str, str]:
    keys = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {key: os.environ.get(prefix + key) for key in keys}
    missing = [prefix + key for key, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"],
        "port": values["PGPORT"],
        "dbname": values["PGDATABASE"],
        "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
    }
    if prefix == "SOURCE_" and os.environ.get("SOURCE_PGSSLMODE"):
        result["sslmode"] = os.environ["SOURCE_PGSSLMODE"]
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date(today.year + 1, 1, 1)


def extract_sql(horizon_start: date, horizon_end: date) -> str:
    sql = EXTRACT.read_text(encoding="utf-8")
    sql = sql[sql.index("WITH pz AS (") :].strip().rstrip(";")
    return (
        sql.replace("$1::date", f"DATE '{horizon_start.isoformat()}'")
        .replace("$2::date", f"DATE '{horizon_end.isoformat()}'")
    )


def source_controls(cursor, query: str) -> tuple[int, int, int]:
    cursor.execute(
        f"""
        SELECT count(*)::bigint,
               coalesce(sum(training_count), 0)::bigint,
               count(*) FILTER (WHERE training_count <= 0)::bigint
        FROM ({query}) q
        """
    )
    target_rows, source_rows, invalid_counts = cursor.fetchone()
    if not target_rows or source_rows <= 0 or invalid_counts:
        raise RuntimeError("Unexpected source aggregate control")
    return source_rows, target_rows, source_rows


def require_stage_integrity(cursor) -> None:
    cursor.execute(
        """
        SELECT count(*)
        FROM (
            SELECT 1
            FROM _ip_training_daily_stage
            GROUP BY training_date, club_id, employee_id, client_key, service_id
            HAVING count(*) > 1
        ) duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Duplicate logical key in source stage")
    cursor.execute(
        """
        SELECT count(*)
        FROM _ip_training_daily_stage
        WHERE training_date IS NULL OR club_id IS NULL OR employee_id IS NULL
           OR employee_name IS NULL OR client_key IS NULL OR client_code IS NULL
           OR service_id IS NULL OR service_name IS NULL OR training_count IS NULL
           OR training_count <= 0 OR client_key <> client_code
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Fact-contract violation in source stage")


def target_controls(cursor, relation: str) -> tuple[int, int]:
    cursor.execute(
        f"""
        SELECT count(*)::bigint, coalesce(sum(training_count), 0)::bigint
        FROM {relation}
        """
    )
    return cursor.fetchone()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="perform approved target DML; omitting this flag performs no writes",
    )
    args = parser.parse_args()
    if not args.apply:
        raise SystemExit("Refusing DML without --apply")

    horizon_start, horizon_end = br003_horizon(
        datetime.now(ZoneInfo("Europe/Moscow")).date()
    )
    query = extract_sql(horizon_start, horizon_end)

    with psycopg.connect(**config("SOURCE_")) as source, psycopg.connect(
        **config("MART_")
    ) as target:
        with source.cursor() as source_cur, target.cursor() as target_cur:
            source_cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            expected_source_rows, expected_target_rows, expected_training_count = (
                source_controls(source_cur, query)
            )
            print(
                "SOURCE_SNAPSHOT "
                f"horizon={horizon_start}..{horizon_end} "
                f"source_rows={expected_source_rows} "
                f"target_rows={expected_target_rows} "
                f"training_count={expected_training_count}",
                flush=True,
            )

            target_cur.execute("BEGIN")
            target_cur.execute(
                "SELECT pg_advisory_xact_lock(hashtext(%s))",
                ("mart.ip_training_daily:refresh",),
            )
            target_cur.execute(
                """
                CREATE TEMP TABLE _ip_training_daily_stage (
                    LIKE mart.ip_training_daily INCLUDING DEFAULTS
                ) ON COMMIT DROP
                """
            )
            with target_cur.copy(
                f"COPY _ip_training_daily_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
            ) as target_copy, source_cur.copy(
                f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)"
            ) as source_copy:
                for block in source_copy:
                    target_copy.write(block)

            require_stage_integrity(target_cur)
            stage_rows, stage_training_count = target_controls(
                target_cur, "_ip_training_daily_stage"
            )
            if (stage_rows, stage_training_count) != (
                expected_target_rows,
                expected_training_count,
            ):
                raise RuntimeError("Staging controls differ from the source snapshot")
            print(
                f"STAGE_PASS rows={stage_rows} training_count={stage_training_count} "
                "duplicate_keys=0 contract_violations=0",
                flush=True,
            )

            target_cur.execute("DELETE FROM mart.ip_training_daily")
            target_cur.execute(
                f"""
                INSERT INTO mart.ip_training_daily ({COLUMNS})
                SELECT {COLUMNS}
                FROM _ip_training_daily_stage
                """
            )
            persisted = target_controls(target_cur, "mart.ip_training_daily")
            if persisted != (expected_target_rows, expected_training_count):
                raise RuntimeError("Persistent controls differ from the source snapshot")
            target.commit()
            print(
                f"DML_COMMITTED rows={persisted[0]} training_count={persisted[1]}",
                flush=True,
            )
            source.rollback()


if __name__ == "__main__":
    main()
