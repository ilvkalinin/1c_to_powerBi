#!/usr/bin/env python3
"""Atomically rebuild mart.dpfu_plan_assignment from one 1C source snapshot."""

from __future__ import annotations

import argparse
import os
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/dpfu_plan_assignment_extract.sql"
COLUMNS = """
plan_date, club_id, activity_id, employee_id, planned_client_key,
planned_client_code, plan_line_discriminator, planned_revenue
""".replace("\n", " ")


def config(prefix: str) -> dict[str, str]:
    keys = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {key: os.environ.get(prefix + key) for key in keys}
    missing = [prefix + key for key, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"],
        "dbname": values["PGDATABASE"], "user": values["PGUSER"],
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
    sql = sql[sql.index("SELECT r._fld6613::date") :].strip().rstrip(";")
    return (
        sql.replace("$1::date", f"DATE '{horizon_start.isoformat()}'")
        .replace("$2::date", f"DATE '{horizon_end.isoformat()}'")
    )


def source_controls(cursor, query: str) -> tuple[int, object, int, int]:
    cursor.execute(
        f"""
        SELECT count(*)::bigint, coalesce(sum(planned_revenue), 0)::numeric(18,2),
               count(*) FILTER (WHERE planned_revenue < 0)::bigint,
               count(*) FILTER (WHERE planned_revenue = 0)::bigint
        FROM ({query}) q
        """
    )
    values = cursor.fetchone()
    if not values[0]:
        raise RuntimeError("Unexpected empty source projection")
    return values


def require_client_code_quality(cursor, query: str) -> None:
    cursor.execute(
        f"""
        SELECT count(DISTINCT planned_client_key)::bigint,
               count(DISTINCT planned_client_code)::bigint,
               count(*) FILTER (WHERE btrim(planned_client_code) = '')::bigint
        FROM ({query}) q
        """
    )
    client_ids, client_codes, blank_codes = cursor.fetchone()
    if not client_ids or client_ids != client_codes or blank_codes:
        raise RuntimeError("Planned-client code is blank or not one-to-one in source snapshot")


def require_stage_integrity(cursor) -> None:
    cursor.execute(
        """
        SELECT count(*) FROM (
            SELECT 1 FROM _dpfu_plan_assignment_stage
            GROUP BY plan_date, club_id, activity_id, employee_id,
                     planned_client_key, plan_line_discriminator
            HAVING count(*) > 1
        ) duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Duplicate logical key in source stage")
    cursor.execute(
        """
        SELECT count(*) FROM _dpfu_plan_assignment_stage
        WHERE plan_date IS NULL OR club_id IS NULL OR activity_id IS NULL
           OR employee_id IS NULL OR planned_client_key IS NULL
           OR planned_client_code IS NULL OR plan_line_discriminator IS NULL
           OR planned_revenue IS NULL
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Fact-contract violation in source stage")


def target_controls(cursor, relation: str) -> tuple[int, object, int, int]:
    cursor.execute(
        f"""
        SELECT count(*)::bigint, coalesce(sum(planned_revenue), 0)::numeric(18,2),
               count(*) FILTER (WHERE planned_revenue < 0)::bigint,
               count(*) FILTER (WHERE planned_revenue = 0)::bigint
        FROM {relation}
        """
    )
    return cursor.fetchone()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform approved target DML")
    args = parser.parse_args()
    if not args.apply:
        raise SystemExit("Refusing DML without --apply")

    horizon_start, horizon_end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    query = extract_sql(horizon_start, horizon_end)
    with psycopg.connect(**config("SOURCE_")) as source, psycopg.connect(**config("MART_")) as target:
        with source.cursor() as source_cur, target.cursor() as target_cur:
            source_cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            require_client_code_quality(source_cur, query)
            expected = source_controls(source_cur, query)
            print(f"SOURCE_SNAPSHOT horizon={horizon_start}..{horizon_end} rows={expected[0]} planned_revenue={expected[1]} negative_rows={expected[2]} zero_rows={expected[3]}", flush=True)

            target_cur.execute("BEGIN")
            target_cur.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.dpfu_plan_assignment:refresh",))
            target_cur.execute("CREATE TEMP TABLE _dpfu_plan_assignment_stage (LIKE mart.dpfu_plan_assignment INCLUDING DEFAULTS) ON COMMIT DROP")
            with target_cur.copy(f"COPY _dpfu_plan_assignment_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as target_copy, source_cur.copy(f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)") as source_copy:
                for block in source_copy:
                    target_copy.write(block)

            require_stage_integrity(target_cur)
            stage = target_controls(target_cur, "_dpfu_plan_assignment_stage")
            if stage != expected:
                raise RuntimeError("Staging controls differ from the source snapshot")
            print(f"STAGE_PASS rows={stage[0]} planned_revenue={stage[1]} negative_rows={stage[2]} zero_rows={stage[3]} duplicate_keys=0 contract_violations=0", flush=True)

            target_cur.execute("DELETE FROM mart.dpfu_plan_assignment")
            target_cur.execute(f"INSERT INTO mart.dpfu_plan_assignment ({COLUMNS}) SELECT {COLUMNS} FROM _dpfu_plan_assignment_stage")
            persisted = target_controls(target_cur, "mart.dpfu_plan_assignment")
            if persisted != stage:
                raise RuntimeError("Persistent fact controls differ from the source snapshot")
            target.commit()
            print(f"DML_COMMITTED rows={persisted[0]} planned_revenue={persisted[1]}", flush=True)
            source.rollback()


if __name__ == "__main__":
    main()
