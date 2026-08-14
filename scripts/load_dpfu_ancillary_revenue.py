#!/usr/bin/env python3
"""Atomically rebuild mart.ancillary_revenue_movement from the two 1C branches."""

from __future__ import annotations

import argparse
import os
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
EXTRACTS = (
    ROOT / "sql/marts/dpfu_ancillary_revenue_extract_7575.sql",
    ROOT / "sql/marts/dpfu_ancillary_revenue_extract_7646.sql",
)
RECONCILIATION = ROOT / "sql/tests/dpfu_ancillary_revenue_reconciliation.sql"
COLUMNS = """
source_kind, recorder_id, line_no, service_date, club_id, client_key,
client_code, employee_id, employee_name, service_id, service_name,
activity_id, activity_name, training_format_id, training_format_name,
calculation_category, age_category, service_quantity, revenue_amount
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
    if prefix == "SOURCE_":
        sslmode = os.environ.get("SOURCE_PGSSLMODE")
        if sslmode:
            result["sslmode"] = sslmode
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date(today.year + 1, 1, 1)


def bound_sql(path: Path, horizon_start: date, horizon_end: date) -> str:
    return (
        path.read_text(encoding="utf-8")
        .replace("$1::date", f"DATE '{horizon_start.isoformat()}'")
        .replace("$2::date", f"DATE '{horizon_end.isoformat()}'")
    )


def control_queries() -> list[str]:
    source_section = RECONCILIATION.read_text(encoding="utf-8").split(
        "-- Target controls."
    )[0]
    queries = []
    for chunk in source_section.split(";"):
        if "SELECT\n    '7575'" in chunk or "SELECT\n    '7646'" in chunk:
            queries.append(
                chunk[chunk.index("SELECT") :]
                .replace("$1::date", "%s::date")
                .replace("$2::date", "%s::date")
            )
    if len(queries) != 2:
        raise RuntimeError("Cannot locate two independent source controls")
    return queries


def controls(cursor, relation: str) -> dict[str, tuple[int, object, object]]:
    cursor.execute(
        f"""
        SELECT source_kind, count(*)::bigint,
               sum(service_quantity)::numeric(18, 3),
               sum(revenue_amount)::numeric(18, 2)
        FROM {relation}
        GROUP BY source_kind
        ORDER BY source_kind
        """
    )
    return {kind: (rows, quantity, revenue) for kind, rows, quantity, revenue in cursor}


def require_stage_integrity(cursor) -> None:
    cursor.execute(
        """
        SELECT count(*)
        FROM (
            SELECT 1
            FROM _ancillary_revenue_movement_stage
            GROUP BY source_kind, recorder_id, line_no
            HAVING count(*) > 1
        ) duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Duplicate technical key in source stage")
    cursor.execute(
        """
        SELECT count(*)
        FROM _ancillary_revenue_movement_stage
        WHERE source_kind IS NULL OR recorder_id IS NULL OR line_no IS NULL
           OR service_date IS NULL OR club_id IS NULL OR client_key IS NULL
           OR client_code IS NULL OR service_id IS NULL OR service_name IS NULL
           OR activity_id IS NULL OR activity_name IS NULL
           OR calculation_category IS NULL OR age_category IS NULL
           OR service_quantity IS NULL OR revenue_amount IS NULL
           OR source_kind NOT IN ('7575', '7646')
           OR calculation_category NOT IN ('Прочая услуга', 'Аренда')
           OR age_category NOT IN ('Дети', 'Юниоры', 'Взрослые')
           OR client_key <> client_code
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Fact-contract violation in source stage")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="perform the approved target DML; omitting this flag performs no writes",
    )
    args = parser.parse_args()
    if not args.apply:
        raise SystemExit("Refusing DML without --apply")

    horizon_start, horizon_end = br003_horizon(
        datetime.now(ZoneInfo("Europe/Moscow")).date()
    )
    source_config = config("SOURCE_")
    target_config = config("MART_")

    with psycopg.connect(**source_config) as source, psycopg.connect(
        **target_config
    ) as target:
        with source.cursor() as source_cur, target.cursor() as target_cur:
            source_cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            expected: dict[str, tuple[int, object, object]] = {}
            for query in control_queries():
                source_cur.execute(query, (horizon_start, horizon_end))
                kind, rows, quantity, revenue = source_cur.fetchone()
                expected[kind] = (rows, quantity, revenue)
            if set(expected) != {"7575", "7646"} or any(
                rows == 0 for rows, _, _ in expected.values()
            ):
                raise RuntimeError("Unexpected independent source controls")
            print(
                f"SOURCE_SNAPSHOT horizon={horizon_start}..{horizon_end}",
                flush=True,
            )
            for kind in sorted(expected):
                rows, quantity, revenue = expected[kind]
                print(
                    f"SOURCE_CONTROL {kind} rows={rows} quantity={quantity} revenue={revenue}",
                    flush=True,
                )

            print("TARGET_STAGE_CREATE", flush=True)
            target_cur.execute("BEGIN")
            target_cur.execute(
                "SELECT pg_advisory_xact_lock(hashtext(%s))",
                ("mart.ancillary_revenue_movement:refresh",),
            )
            target_cur.execute(
                """
                CREATE TEMP TABLE _ancillary_revenue_movement_stage (
                    LIKE mart.ancillary_revenue_movement INCLUDING DEFAULTS
                ) ON COMMIT DROP
                """
            )
            target_cur.execute(
                """
                CREATE TEMP TABLE _ancillary_revenue_movement_expected (
                    source_kind text PRIMARY KEY,
                    movement_rows bigint NOT NULL,
                    service_quantity numeric(18, 3) NOT NULL,
                    revenue_amount numeric(18, 2) NOT NULL
                ) ON COMMIT DROP
                """
            )
            target_cur.executemany(
                "INSERT INTO _ancillary_revenue_movement_expected VALUES (%s, %s, %s, %s)",
                [(kind, *expected[kind]) for kind in sorted(expected)],
            )
            print("TARGET_STAGE_READY", flush=True)

            copied: dict[str, int] = {}
            for path in EXTRACTS:
                print(f"SOURCE_STREAM_START {path.name}", flush=True)
                extract_sql = bound_sql(path, horizon_start, horizon_end).rstrip()
                if extract_sql.endswith(";"):
                    extract_sql = extract_sql[:-1]
                with target_cur.copy(
                    f"COPY _ancillary_revenue_movement_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
                ) as target_copy, source_cur.copy(
                    f"COPY ({extract_sql}) TO STDOUT WITH (FORMAT BINARY)"
                ) as source_copy:
                    for block in source_copy:
                        target_copy.write(block)
                kind = "7575" if path.name.endswith("7575.sql") else "7646"
                copied[kind] = expected[kind][0]
                print(f"SOURCE_STREAM_DONE {kind}", flush=True)

            staged = controls(target_cur, "_ancillary_revenue_movement_stage")
            if staged != expected:
                raise RuntimeError("Staging controls differ from source snapshot")
            require_stage_integrity(target_cur)
            print(
                f"STAGE_PASS rows={sum(copied.values())} duplicate_keys=0 contract_violations=0",
                flush=True,
            )

            target_cur.execute("DELETE FROM mart.ancillary_revenue_movement")
            target_cur.execute(
                f"""
                INSERT INTO mart.ancillary_revenue_movement ({COLUMNS})
                SELECT {COLUMNS}
                FROM _ancillary_revenue_movement_stage
                """
            )
            persisted = controls(target_cur, "mart.ancillary_revenue_movement")
            if persisted != expected:
                raise RuntimeError("Persistent controls differ from source snapshot")
            target.commit()
            print(
                f"DML_COMMITTED rows={sum(rows for rows, _, _ in persisted.values())}",
                flush=True,
            )
            for kind in sorted(persisted):
                rows, quantity, revenue = persisted[kind]
                print(
                    f"TARGET_CONTROL {kind} rows={rows} quantity={quantity} revenue={revenue}",
                    flush=True,
                )
            source.rollback()


if __name__ == "__main__":
    main()
