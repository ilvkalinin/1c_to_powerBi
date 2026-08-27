#!/usr/bin/env python3
"""Atomically rebuild mart.client_base_daily after separate DML approval."""

from __future__ import annotations

import argparse
import os
import shutil
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
CHILD_PACKAGE_AGE_CONTROLS = ROOT / "sql/marts/client_base_daily_child_package_age_controls.sql"
TARGET_REPLACE = ROOT / "sql/marts/client_base_daily_target_replace.sql"
TARGET_AGE_DDL = ROOT / "sql/marts/client_base_daily_child_package_age_ddl.sql"
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
    return date(today.year - years_back, 1, 1), date.fromordinal(today.toordinal() + 1)


def rendered(path: Path, horizon_start: date, horizon_end: date) -> str:
    return (
        path.read_text(encoding="utf-8")
        .strip()
        .rstrip(";")
        .replace("$1::date", f"DATE '{horizon_start.isoformat()}'")
        .replace("$2::date", f"DATE '{horizon_end.isoformat()}'")
    )


def reviewed_statements(path: Path, horizon_start: date, horizon_end: date) -> list[str]:
    sql_without_comments = "\n".join(
        line for line in rendered(path, horizon_start, horizon_end).splitlines()
        if not line.lstrip().startswith("--")
    )
    return [statement.strip() for statement in sql_without_comments.split(";") if statement.strip()]


def source_totals(cursor, controls_sql: str, start: date, end: date) -> dict[tuple[date, str], int]:
    cursor.execute(controls_sql)
    result = {(report_date, scope): count for report_date, scope, count in cursor}
    expected_rows = (end - start).days * 2
    if len(result) != expected_rows or any(count <= 0 for count in result.values()):
        raise RuntimeError("Source control is incomplete or contains a nonpositive daily total")
    return result


def source_scope_totals(cursor, controls_sql: str) -> dict[str, int]:
    cursor.execute(controls_sql)
    result = {scope: count for scope, count in cursor}
    if set(result) != {"club", "network"} or any(count < 0 for count in result.values()):
        raise RuntimeError("Child-package source control is incomplete or invalid")
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


def child_package_age_totals(cursor, relation: str, start: date, end: date) -> dict[str, int]:
    cursor.execute(
        f"""
        SELECT scope_level, coalesce(sum(client_count), 0)::bigint
        FROM {relation}
        WHERE report_date >= %s AND report_date < %s
          AND age_group = 'Дети'
          AND (age_years IS NULL OR age_years >= 14)
        GROUP BY scope_level
        """,
        (start, end),
    )
    result = {scope: count for scope, count in cursor}
    return {scope: result.get(scope, 0) for scope in ("club", "network")}


def has_br038_age_constraint(cursor) -> bool:
    cursor.execute(
        """
        SELECT pg_get_constraintdef(con.oid)
        FROM pg_constraint AS con
        JOIN pg_class AS rel ON rel.oid = con.conrelid
        JOIN pg_namespace AS ns ON ns.oid = rel.relnamespace
        WHERE ns.nspname = 'mart'
          AND rel.relname = 'client_base_daily'
          AND con.conname = 'client_base_daily_age_ck'
        """
    )
    row = cursor.fetchone()
    if row is None:
        return False
    definition = row[0]
    return "age_years IS NOT NULL" in definition and "'Дети'" in definition


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
               age_group = 'Дети'
               OR (age_years IS NULL AND age_group = 'Не указано')
               OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
               OR (age_years >= 18 AND age_group = 'Взрослые')
           )
           OR report_date < %s OR report_date >= %s
        """,
        (start, end),
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Fact-contract violation in source stage")


def month_batches(start: date, end: date) -> list[tuple[date, date]]:
    batches: list[tuple[date, date]] = []
    batch_start = start
    while batch_start < end:
        next_month = date(
            batch_start.year + (batch_start.month == 12),
            batch_start.month % 12 + 1,
            1,
        )
        batches.append((batch_start, min(next_month, end)))
        batch_start = next_month
    return batches


def require_batch_space(directory: Path) -> None:
    # The measured representative month is only a few MiB. One GiB leaves a
    # conservative bounded margin for exactly one binary transport file.
    free_bytes = shutil.disk_usage(directory).free
    if free_bytes < 1_073_741_824:
        raise RuntimeError("Less than 1 GiB is free for the current COPY batch")


def copy_source_batch(source, start: date, end: date, path: Path) -> tuple[int, int, float]:
    query = rendered(EXTRACT, start, end)
    started_at = time.monotonic()
    with source.cursor() as cursor, path.open("wb") as output:
        with cursor.copy(f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)") as copied:
            for block in copied:
                output.write(block)
        rows = cursor.rowcount
    elapsed = time.monotonic() - started_at
    return rows, path.stat().st_size, elapsed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rebuild",
        action="store_true",
        help="perform the separately approved atomic rebuild of the existing fact",
    )
    if not parser.parse_args().rebuild:
        raise SystemExit("Refusing DML without --rebuild")

    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    source_controls_sql = rendered(SOURCE_CONTROLS, start, end)
    child_package_age_controls_sql = rendered(CHILD_PACKAGE_AGE_CONTROLS, start, end)
    target_statements = reviewed_statements(TARGET_REPLACE, start, end)
    if len(target_statements) != 2:
        raise RuntimeError("Unexpected target replacement statement count")
    target_ddl_statements = reviewed_statements(TARGET_AGE_DDL, start, end)
    if len(target_ddl_statements) != 2 or not all(
        "client_base_daily_age_ck" in statement for statement in target_ddl_statements
    ):
        raise RuntimeError("Unexpected child-package age DDL")

    started_at = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="client_base_daily_") as temporary_directory:
        directory = Path(temporary_directory)
        with connect_with_retry(
            lambda: psycopg.connect(**config("SOURCE_")), endpoint="source"
        ) as source, connect_with_retry(
            lambda: psycopg.connect(**config("MART_")), endpoint="mart"
        ) as target:
            try:
                with source.cursor() as source_cursor:
                    source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                    source_cursor.execute("SET LOCAL statement_timeout = '120000'")
                    expected = source_totals(source_cursor, source_controls_sql, start, end)
                    expected_child_package_age = source_scope_totals(
                        source_cursor, child_package_age_controls_sql
                    )
                print(
                    f"SOURCE_SNAPSHOT horizon={start}..{end} daily_scope_totals={len(expected)}",
                    flush=True,
                )
                for scope in ("club", "network"):
                    print(
                        f"SOURCE_CONTROL scope={scope} client_count="
                        f"{sum(count for (_, item_scope), count in expected.items() if item_scope == scope)}",
                        flush=True,
                    )
                    print(
                        f"SOURCE_BR038_CONTROL scope={scope} age_14_or_unknown_children_client_days="
                        f"{expected_child_package_age[scope]}",
                        flush=True,
                    )
                with target.cursor() as target_cursor:
                    target_cursor.execute("BEGIN")
                    target_cursor.execute("SET LOCAL lock_timeout = '60s'")
                    target_cursor.execute(
                        "SELECT to_regclass('mart.client_base_daily') IS NOT NULL"
                    )
                    if not target_cursor.fetchone()[0]:
                        raise RuntimeError("Existing target fact is absent; this package authorizes no DDL")
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
                    copied_rows = 0
                    for batch_start, batch_end in month_batches(start, end):
                        require_batch_space(directory)
                        transfer_path = directory / f"{batch_start:%Y%m}.copy"
                        try:
                            batch_rows, batch_bytes, batch_elapsed = copy_source_batch(
                                source, batch_start, batch_end, transfer_path
                            )
                            with target_cursor.copy(
                                f"COPY _client_base_daily_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
                            ) as target_copy, transfer_path.open("rb") as transfer_input:
                                while block := transfer_input.read(1_048_576):
                                    target_copy.write(block)
                            if target_cursor.rowcount != batch_rows:
                                raise RuntimeError(
                                    f"Target batch COPY differs: {target_cursor.rowcount} != {batch_rows}"
                                )
                            copied_rows += batch_rows
                            print(
                                f"BATCH_PASS start={batch_start} end={batch_end} rows={batch_rows} "
                                f"bytes={batch_bytes} elapsed_seconds={batch_elapsed:.3f}",
                                flush=True,
                            )
                        finally:
                            transfer_path.unlink(missing_ok=True)

                    require_stage_integrity(target_cursor, start, end)
                    staged = totals(target_cursor, "_client_base_daily_stage", start, end)
                    if staged != expected:
                        raise RuntimeError("Staging daily totals differ from independent source control")
                    staged_child_package_age = child_package_age_totals(
                        target_cursor, "_client_base_daily_stage", start, end
                    )
                    if staged_child_package_age != expected_child_package_age:
                        raise RuntimeError("Staging BR-038 child-package control differs from source snapshot")
                    print(
                        f"STAGE_PASS rows={copied_rows} daily_scope_totals={len(staged)} "
                        "binary_transport=monthly_bounded_files",
                        flush=True,
                    )
                    if has_br038_age_constraint(target_cursor):
                        print("TARGET_BR038_DDL_REUSED", flush=True)
                    else:
                        for statement in target_ddl_statements:
                            target_cursor.execute(statement)
                        print("TARGET_BR038_DDL_APPLIED validation=deferred", flush=True)
                    for statement in target_statements:
                        target_cursor.execute(statement)
                    persisted = totals(target_cursor, "mart.client_base_daily", start, end)
                    if persisted != expected:
                        raise RuntimeError("Persistent daily totals differ from source snapshot")
                    persisted_child_package_age = child_package_age_totals(
                        target_cursor, "mart.client_base_daily", start, end
                    )
                    if persisted_child_package_age != expected_child_package_age:
                        raise RuntimeError("Persistent BR-038 child-package control differs from source snapshot")
                    target.commit()
                    source.rollback()
                    print(
                        f"DML_COMMITTED horizon={start}..{end} daily_scope_totals={len(persisted)} "
                        f"elapsed_seconds={time.monotonic() - started_at:.3f}",
                        flush=True,
                    )
            except Exception:
                target.rollback()
                source.rollback()
                raise


if __name__ == "__main__":
    main()
