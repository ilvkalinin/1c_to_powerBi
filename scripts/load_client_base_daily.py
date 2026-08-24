#!/usr/bin/env python3
"""Atomically rebuild mart.client_base_daily after separate DML approval."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
import time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
EXTRACT = ROOT / "sql/marts/client_base_daily_extract.sql"
SOURCE_CONTROLS = ROOT / "sql/marts/client_base_daily_source_controls.sql"
TARGET_REPLACE = ROOT / "sql/marts/client_base_daily_target_replace.sql"
COLUMNS = "scope_level, report_date, club_id, age_years, age_group, gender, client_count"


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"],
        "port": values["PGPORT"],
        "dbname": values["PGDATABASE"],
        "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
    }
    sslmode = os.environ.get(prefix + "PGSSLMODE")
    if sslmode:
        result["sslmode"] = sslmode
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date(today.year + 1, 1, 1)


def rendered(path: Path, horizon_start: date, horizon_end: date) -> str:
    return (
        path.read_text(encoding="utf-8")
        .strip()
        .rstrip(";")
        .replace("$1::date", f"DATE '{horizon_start.isoformat()}'")
        .replace("$2::date", f"DATE '{horizon_end.isoformat()}'")
    )


def source_totals(cursor, controls_sql: str, start: date, end: date) -> dict[tuple[date, str], int]:
    cursor.execute(controls_sql)
    result = {(report_date, scope): count for report_date, scope, count in cursor}
    expected_rows = (end - start).days * 2
    if len(result) != expected_rows or any(count <= 0 for count in result.values()):
        raise RuntimeError("Source control is incomplete or contains a nonpositive daily total")
    return result


def totals(cursor, relation: str, start: date, end: date) -> dict[tuple[date, str], int]:
    cursor.execute(
        f"""
        SELECT report_date, scope_level, sum(client_count)::bigint
        FROM {relation}
        WHERE report_date >= %s AND report_date < %s
        GROUP BY report_date, scope_level
        """,
        (start, end),
    )
    return {(report_date, scope): count for report_date, scope, count in cursor}


def require_stage_integrity(cursor, start: date, end: date) -> None:
    cursor.execute(
        """
        SELECT count(*)
        FROM (
            SELECT 1
            FROM _client_base_daily_stage
            GROUP BY scope_level, report_date, club_id, age_years, age_group, gender
            HAVING count(*) > 1
        ) AS duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Duplicate logical key in source stage")
    cursor.execute(
        """
        SELECT count(*)
        FROM _client_base_daily_stage
        WHERE report_date IS NULL
           OR scope_level NOT IN ('club', 'network')
           OR (scope_level = 'club' AND club_id IS NULL)
           OR (scope_level = 'network' AND club_id IS NOT NULL)
           OR age_group IS NULL
           OR gender NOT IN ('Женский', 'Мужской', 'Не указано')
           OR client_count IS NULL OR client_count <= 0
           OR NOT (
               (age_years IS NULL AND age_group = 'Не указано')
               OR (age_years < 14 AND age_group = 'Дети')
               OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
               OR (age_years >= 18 AND age_group = 'Взрослые')
           )
           OR report_date < %s OR report_date >= %s
        """,
        (start, end),
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Fact-contract violation in source stage")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform separately approved target DML")
    if not parser.parse_args().apply:
        raise SystemExit("Refusing DML without --apply")

    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    extract_sql = rendered(EXTRACT, start, end)
    source_controls_sql = rendered(SOURCE_CONTROLS, start, end)
    target_statements = [
        statement.strip()
        for statement in rendered(TARGET_REPLACE, start, end).split(";")
        if statement.strip()
    ]
    if len(target_statements) != 2:
        raise RuntimeError("Unexpected target replacement statement count")

    started_at = time.monotonic()
    transfer_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix="client_base_daily_", suffix=".copy", delete=False
        ) as transfer_file:
            transfer_path = Path(transfer_file.name)
            with connect_with_retry(
                lambda: psycopg.connect(**config("SOURCE_")), endpoint="source"
            ) as source:
                with source.cursor() as source_cursor:
                    source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                    source_cursor.execute("SET LOCAL statement_timeout = '60000'")
                    expected = source_totals(source_cursor, source_controls_sql, start, end)
                    print(
                        f"SOURCE_SNAPSHOT horizon={start}..{end} daily_scope_totals={len(expected)}",
                        flush=True,
                    )
                    with source_cursor.copy(
                        f"COPY ({extract_sql}) TO STDOUT WITH (FORMAT BINARY)"
                    ) as source_copy:
                        for block in source_copy:
                            transfer_file.write(block)
                    transfer_file.flush()
                    source.rollback()
            print(
                f"SOURCE_COPY_READY bytes={transfer_path.stat().st_size}",
                flush=True,
            )

        with connect_with_retry(
            lambda: psycopg.connect(**config("MART_")), endpoint="mart"
        ) as target:
            with target.cursor() as target_cursor:
                target_cursor.execute("BEGIN")
                target_cursor.execute(
                    "SELECT pg_advisory_xact_lock(hashtext(%s))",
                    ("mart.client_base_daily:refresh",),
                )
                target_cursor.execute(
                    "CREATE TEMP TABLE _client_base_daily_stage (LIKE mart.client_base_daily INCLUDING DEFAULTS) ON COMMIT DROP"
                )
                target_cursor.execute(
                    """
                    CREATE TEMP TABLE _client_base_daily_expected (
                        report_date date NOT NULL,
                        scope_level text NOT NULL,
                        client_count bigint NOT NULL,
                        PRIMARY KEY (report_date, scope_level)
                    ) ON COMMIT DROP
                    """
                )
                target_cursor.executemany(
                    "INSERT INTO _client_base_daily_expected VALUES (%s, %s, %s)",
                    [(report_date, scope, count) for (report_date, scope), count in expected.items()],
                )
                with target_cursor.copy(
                    f"COPY _client_base_daily_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
                ) as target_copy, transfer_path.open("rb") as transfer_input:
                    while block := transfer_input.read(1_048_576):
                        target_copy.write(block)

                require_stage_integrity(target_cursor, start, end)
                staged = totals(target_cursor, "_client_base_daily_stage", start, end)
                if staged != expected:
                    raise RuntimeError("Staging daily totals differ from independent source control")
                print(
                    f"STAGE_PASS daily_scope_totals={len(staged)} binary_transfer=local_aggregate_file",
                    flush=True,
                )

                for statement in target_statements:
                    target_cursor.execute(statement)
                persisted = totals(target_cursor, "mart.client_base_daily", start, end)
                if persisted != expected:
                    raise RuntimeError("Persistent daily totals differ from source snapshot")
                target.commit()
                elapsed = time.monotonic() - started_at
                print(
                    f"DML_COMMITTED horizon={start}..{end} daily_scope_totals={len(persisted)} elapsed_seconds={elapsed:.3f}",
                    flush=True,
                )
    finally:
        if transfer_path is not None:
            transfer_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
