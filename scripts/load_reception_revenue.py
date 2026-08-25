#!/usr/bin/env python3
"""Atomically replace only the reception scope in the shared ancillary fact."""

from __future__ import annotations

import argparse
import os
import time
import sys
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
EXTRACTS = (
    ROOT / "sql/marts/reception_revenue_extract_7575.sql",
    ROOT / "sql/marts/reception_revenue_extract_7646.sql",
)
RECONCILIATION = ROOT / "sql/tests/reception_revenue_reconciliation.sql"
COLUMNS = """
source_kind, recorder_id, line_no, service_date, club_id, client_key,
client_code, employee_id, employee_name, service_id, service_name,
activity_id, activity_name, training_format_id, training_format_name,
calculation_category, age_category, service_quantity, revenue_amount,
revenue_scope, reception_category_key
""".replace("\n", " ")
CATEGORIES = {
    "Соляная пещера", "Возмещение ущерба", "Солярий", "Аренда замка",
    "Аренда полотенец и халатов", "Аренда шкафчиков", "Товары рецепции", "Другое",
}


def config(prefix: str) -> dict[str, str]:
    keys = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {key: os.environ.get(prefix + key) for key in keys}
    missing = [prefix + key for key, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {"host": values["PGHOST"], "port": values["PGPORT"],
              "dbname": values["PGDATABASE"], "user": values["PGUSER"],
              "password": values["PGPASSWORD"]}
    if prefix == "SOURCE_" and os.environ.get("SOURCE_PGSSLMODE"):
        result["sslmode"] = os.environ["SOURCE_PGSSLMODE"]
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date(today.year + 1, 1, 1)


def bound_sql(path: Path, start: date, end: date) -> str:
    return (path.read_text(encoding="utf-8")
            .replace("$1::date", f"DATE '{start.isoformat()}'")
            .replace("$2::date", f"DATE '{end.isoformat()}'"))


def source_control_sql(start: date, end: date) -> str:
    text = RECONCILIATION.read_text(encoding="utf-8")
    source_section = text.split("-- Target controls.")[0].split("-- Source controls.")[1]
    return (source_section[source_section.index("WITH source_rows AS"):].strip().rstrip(";")
            .replace("$1::date", f"DATE '{start.isoformat()}'")
            .replace("$2::date", f"DATE '{end.isoformat()}'"))


def scoped_controls(cursor, relation: str) -> dict[tuple[str, str], tuple[int, object, object]]:
    cursor.execute(f"""
        SELECT source_kind, reception_category_key, count(*)::bigint,
               sum(service_quantity)::numeric(18, 3), sum(revenue_amount)::numeric(18, 2)
        FROM {relation}
        GROUP BY source_kind, reception_category_key
        ORDER BY source_kind, reception_category_key
    """)
    return {(kind, category): (rows, quantity, revenue)
            for kind, category, rows, quantity, revenue in cursor}


def dpfu_controls(cursor) -> dict[str, tuple[int, object, object]]:
    cursor.execute("""
        SELECT source_kind, count(*)::bigint, sum(service_quantity)::numeric(18, 3),
               sum(revenue_amount)::numeric(18, 2)
        FROM mart.ancillary_revenue_movement
        WHERE revenue_scope = 'dpfu'
        GROUP BY source_kind ORDER BY source_kind
    """)
    return {kind: (rows, quantity, revenue) for kind, rows, quantity, revenue in cursor}


def require_stage_integrity(cursor) -> None:
    cursor.execute("""
        SELECT count(*) FROM (
            SELECT 1 FROM _reception_revenue_stage
            GROUP BY source_kind, recorder_id, line_no HAVING count(*) > 1
        ) duplicate_key
    """)
    if cursor.fetchone()[0]:
        raise RuntimeError("Duplicate technical key in reception stage")
    cursor.execute("""
        SELECT count(*) FROM _reception_revenue_stage
        WHERE source_kind NOT IN ('7575', '7646') OR recorder_id IS NULL OR line_no IS NULL
           OR service_date IS NULL OR club_id IS NULL OR employee_id IS NULL
           OR service_id IS NULL OR service_name IS NULL OR service_quantity IS NULL
           OR revenue_amount IS NULL OR revenue_scope <> 'reception'
           OR reception_category_key NOT IN (
               'Соляная пещера', 'Возмещение ущерба', 'Солярий', 'Аренда замка',
               'Аренда полотенец и халатов', 'Аренда шкафчиков', 'Товары рецепции', 'Другое')
           OR client_key IS NOT NULL OR client_code IS NOT NULL
           OR calculation_category IS NOT NULL OR age_category IS NOT NULL
    """)
    if cursor.fetchone()[0]:
        raise RuntimeError("Reception fact-contract violation in source stage")
    cursor.execute("""
        SELECT count(*)
        FROM _reception_revenue_stage s
        JOIN mart.ancillary_revenue_movement d
          ON (d.source_kind, d.recorder_id, d.line_no) = (s.source_kind, s.recorder_id, s.line_no)
        WHERE d.revenue_scope = 'dpfu'
    """)
    if cursor.fetchone()[0]:
        raise RuntimeError("Reception stage collides with an existing DPFU technical key")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform approved DML")
    args = parser.parse_args()
    if not args.apply:
        raise SystemExit("Refusing DML without --apply")

    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    started = time.monotonic()
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        with source.cursor() as source_cur, target.cursor() as target_cur:
            source_cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            source_cur.execute(source_control_sql(start, end))
            expected = {(kind, category): (rows, quantity, revenue)
                        for kind, category, rows, quantity, revenue in source_cur}
            if not expected or {category for _, category in expected} != CATEGORIES:
                raise RuntimeError("Source controls do not cover all eight reception categories")
            print(f"SOURCE_SNAPSHOT horizon={start}..{end}", flush=True)
            for (kind, category), (rows, quantity, revenue) in expected.items():
                print(f"SOURCE_CONTROL {kind} category={category} rows={rows} quantity={quantity} revenue={revenue}", flush=True)

            target_cur.execute("BEGIN")
            target_cur.execute("SELECT pg_advisory_xact_lock(hashtext(%s))",
                               ("mart.ancillary_revenue_movement:reception-refresh",))
            dpfu_before = dpfu_controls(target_cur)
            target_cur.execute("CREATE TEMP TABLE _reception_revenue_stage (LIKE mart.ancillary_revenue_movement INCLUDING DEFAULTS) ON COMMIT DROP")
            print("TARGET_STAGE_READY", flush=True)
            source_copy_started = time.monotonic()
            for path in EXTRACTS:
                print(f"SOURCE_STREAM_START {path.name}", flush=True)
                extract = bound_sql(path, start, end).rstrip().removesuffix(";")
                with target_cur.copy(f"COPY _reception_revenue_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as dst, source_cur.copy(f"COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)") as src:
                    for block in src:
                        dst.write(block)
                print(f"SOURCE_STREAM_DONE {path.name}", flush=True)
            print(f"SOURCE_COPY seconds={time.monotonic() - source_copy_started:.2f}", flush=True)
            validation_started = time.monotonic()
            staged = scoped_controls(target_cur, "_reception_revenue_stage")
            if staged != expected:
                raise RuntimeError("Staging controls differ from independent source snapshot")
            require_stage_integrity(target_cur)
            print(f"STAGE_PASS seconds={time.monotonic() - validation_started:.2f} rows={sum(rows for rows, _, _ in staged.values())} duplicate_keys=0 contract_violations=0 scope_collisions=0", flush=True)

            # Unlike the 508k-row DPFU scope, reception has a measured
            # 150k-row volume.  Keep its staged validation but promote on the
            # mart server, avoiding two unnecessary network COPY passes
            # through a local temporary file.
            promotion_started = time.monotonic()
            target_cur.execute(
                "DELETE FROM mart.ancillary_revenue_movement "
                "WHERE revenue_scope = 'reception'"
            )
            target_cur.execute(
                f"""
                INSERT INTO mart.ancillary_revenue_movement ({COLUMNS})
                SELECT {COLUMNS}
                FROM _reception_revenue_stage
                """
            )
            persisted = scoped_controls(target_cur, "mart.ancillary_revenue_movement WHERE revenue_scope = 'reception'")
            if persisted != expected:
                raise RuntimeError("Persistent reception controls differ from source snapshot")
            if dpfu_controls(target_cur) != dpfu_before:
                raise RuntimeError("DPFU controls changed during reception replacement")
            target.commit()
            seconds = time.monotonic() - started
            print(f"DML_COMMITTED seconds={seconds:.2f} promotion_seconds={time.monotonic() - promotion_started:.2f} rows={sum(rows for rows, _, _ in persisted.values())}", flush=True)
            for (kind, category), (rows, quantity, revenue) in persisted.items():
                print(f"TARGET_CONTROL {kind} category={category} rows={rows} quantity={quantity} revenue={revenue}", flush=True)
            print(f"DPFU_PRESERVED groups={len(dpfu_before)}", flush=True)
            source.rollback()


if __name__ == "__main__":
    main()
