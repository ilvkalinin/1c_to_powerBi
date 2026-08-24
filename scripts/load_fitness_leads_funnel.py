#!/usr/bin/env python3
"""Atomically load the approved fitness-leads task fact and service bridge."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
import time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/fitness_leads_funnel_source_extract.sql"
DDL = ROOT / "sql/marts/fitness_leads_funnel_reviewed_plan.sql"
RECONCILIATION = ROOT / "sql/tests/fitness_leads_funnel_reconciliation.sql"
TARGETS = {
    "task": "mart.fitness_leads_funnel_task",
    "task_service": "mart.fitness_leads_funnel_task_service",
}
COLUMNS = {
    "task": """task_id, task_code, task_created_at, task_date, closed_at, forced_closed_at,
        funnel_id, funnel_name, club_id, club_name, client_key, client_code, tenure_type,
        campaign_id, campaign_name, parent_campaign_name, unsuccessful_reason, funnel_stage_name,
        first_interaction_type, has_booking, training_count, has_paid_training_45d, task_count""",
    "task_service": "task_id, service_name, service_source, service_date",
}


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result = {
        "host": values["PGHOST"],
        "port": values["PGPORT"],
        "dbname": values["PGDATABASE"],
        "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
        "connect_timeout": "15",
    }
    if sslmode := os.environ.get(prefix + "PGSSLMODE"):
        result["sslmode"] = sslmode
    return result


def connect_with_retry(prefix: str) -> psycopg.Connection:
    """Make the initial attempt plus five bounded, observable retries."""
    last_error: Exception | None = None
    for retry in range(6):
        try:
            return psycopg.connect(**config(prefix))
        except psycopg.OperationalError as error:
            last_error = error
            if retry == 5:
                break
            delay = 5
            print(
                f"CONNECTION_RETRY endpoint={prefix.removesuffix('_').lower()} "
                f"retry={retry + 1}/5 delay_seconds={delay}",
                flush=True,
            )
            time.sleep(delay)
    raise RuntimeError(f"Connection failed after five retries for {prefix}") from last_error


def br003_horizon(today: date) -> tuple[date, date]:
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date(today.year + 1, 1, 1)


def sections() -> dict[str, str]:
    parts = re.split(r"(?m)^-- name: ([a-z_]+)\n", EXTRACT.read_text(encoding="utf-8"))
    result = {parts[index]: parts[index + 1].strip().rstrip(";") for index in range(1, len(parts), 2)}
    if set(result) != set(TARGETS):
        raise RuntimeError(f"Unexpected source query names: {sorted(result)}")
    return result


def render_extract(query: str, start: date, end: date) -> str:
    return (query.replace("$1::timestamp without time zone", f"TIMESTAMP '{start}'")
            .replace("$2::timestamp without time zone", f"TIMESTAMP '{end}'"))


def ddl_without_transaction() -> str:
    text = re.sub(r"(?m)^BEGIN;\s*", "", DDL.read_text(encoding="utf-8"), count=1)
    text = re.sub(r"(?m)^COMMIT;\s*$", "", text, count=1)
    if "CREATE TABLE mart.fitness_leads_funnel_task" not in text:
        raise RuntimeError("Unexpected reviewed DDL")
    return text


def source_controls(cursor, task_query: str) -> tuple[int, int, int, int]:
    cursor.execute(
        f"""SELECT count(*)::bigint,
                   count(*) FILTER (WHERE has_booking)::bigint,
                   count(*) FILTER (WHERE has_paid_training_45d)::bigint,
                   coalesce(sum(training_count), 0)::bigint
            FROM ({task_query}) AS task_result"""
    )
    row = cursor.fetchone()
    if row is None:
        raise RuntimeError("Source control returned no row")
    return tuple(int(value) for value in row)


def copy_source(
    start: date, end: date, directory: Path
) -> tuple[dict[str, Path], dict[str, int], tuple[int, int, int, int]]:
    paths, counts = {}, {}
    queries = sections()
    with connect_with_retry("SOURCE_") as source:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            print("SOURCE_TRANSACTION_STARTED isolation=repeatable_read read_only=true", flush=True)
            for ordinal, name in enumerate(("task", "task_service"), 1):
                path = directory / f"{ordinal:02d}_{name}.copy"
                print(f"SOURCE_COPY_STARTED name={name}", flush=True)
                with path.open("wb") as output, cursor.copy(
                    f"COPY ({render_extract(queries[name], start, end)}) TO STDOUT WITH (FORMAT BINARY)"
                ) as copy:
                    while block := copy.read():
                        output.write(block)
                paths[name], counts[name] = path, cursor.rowcount
                print(
                    f"SOURCE_COPY_READY name={name} rows={cursor.rowcount} bytes={path.stat().st_size}",
                    flush=True,
                )
            controls = source_controls(cursor, render_extract(queries["task"], start, end))
            print(
                "SOURCE_CONTROL_READY "
                f"tasks={controls[0]} stage_booking_tasks={controls[1]} "
                f"positive_training_tasks={controls[2]} training_count_sum={controls[3]}",
                flush=True,
            )
            source.rollback()
            print("SOURCE_TRANSACTION_ROLLED_BACK read_only=true", flush=True)
    return paths, counts, controls


def relation_names(cursor) -> set[str]:
    cursor.execute(
        """SELECT c.relname
           FROM pg_class AS c
           JOIN pg_namespace AS n ON n.oid = c.relnamespace
           WHERE n.nspname = 'mart'
             AND c.relname IN ('fitness_leads_funnel_task', 'fitness_leads_funnel_task_service')"""
    )
    return {row[0] for row in cursor}


def copy_target(cursor, name: str, path: Path, expected: int) -> None:
    columns = " ".join(COLUMNS[name].split())
    print(f"TARGET_COPY_STARTED name={name}", flush=True)
    with cursor.copy(f"COPY {TARGETS[name]} ({columns}) FROM STDIN WITH (FORMAT BINARY)") as copy:
        with path.open("rb") as source:
            while block := source.read(1_048_576):
                copy.write(block)
    if cursor.rowcount != expected:
        raise RuntimeError(f"COPY total differs for {name}: {cursor.rowcount} != {expected}")
    print(f"TARGET_COPY_READY name={name} rows={cursor.rowcount} bytes={path.stat().st_size}", flush=True)


def reconciliation_statements(
    task_rows: int, service_rows: int, controls: tuple[int, int, int, int], start: date, end: date
) -> list[str]:
    text = RECONCILIATION.read_text(encoding="utf-8")
    text = (text.replace("$1::bigint", str(task_rows)).replace("$2::bigint", str(service_rows))
            .replace("$3::date", f"DATE '{start}'").replace("$4::date", f"DATE '{end}'")
            .replace("$5::bigint", str(controls[0])).replace("$6::bigint", str(controls[1]))
            .replace("$7::bigint", str(controls[2])).replace("$8::bigint", str(controls[3])))
    return [
        part.strip().rstrip(";")
        for part in re.split(r"(?m)(?=-- FL-R\d+)", text)
        if part.strip().startswith("-- FL-R")
    ]


def require_reconciliation(
    cursor, counts: dict[str, int], controls: tuple[int, int, int, int], start: date, end: date
) -> None:
    statements = reconciliation_statements(counts["task"], counts["task_service"], controls, start, end)
    if len(statements) != 6:
        raise RuntimeError(f"Unexpected reconciliation statement count: {len(statements)}")
    rows = []
    for ordinal, statement in enumerate(statements, 1):
        cursor.execute(statement)
        row = cursor.fetchone()
        rows.append(row)
        print(f"RECONCILIATION_CONTROL_DONE id=FL-R{ordinal:02d} actual={row}", flush=True)
    if (
        not rows[0][-1]
        or any(rows[1])
        or any(rows[2])
        or any(rows[3])
        or not rows[4][-1]
        or rows[5][0] != 0
    ):
        raise RuntimeError(f"Reconciliation failed: {rows}")
    print("RECONCILIATION_PASS FL-R01—FL-R06", flush=True)


def load(
    mode: str,
    paths: dict[str, Path],
    counts: dict[str, int],
    controls: tuple[int, int, int, int],
    start: date,
    end: date,
) -> None:
    expected = {"fitness_leads_funnel_task", "fitness_leads_funnel_task_service"}
    with connect_with_retry("MART_") as target:
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                print("TARGET_TRANSACTION_STARTED", flush=True)
                found = relation_names(cursor)
                if mode == "apply":
                    if found:
                        raise RuntimeError(f"Initial DDL requires absent targets, found: {sorted(found)}")
                    cursor.execute(ddl_without_transaction())
                    print("TARGET_DDL_READY", flush=True)
                elif found != expected:
                    raise RuntimeError(f"Rebuild requires both targets, found: {sorted(found)}")
                else:
                    cursor.execute(
                        """LOCK TABLE mart.fitness_leads_funnel_task_service,
                                      mart.fitness_leads_funnel_task IN ACCESS EXCLUSIVE MODE"""
                    )
                    print("TARGET_LOCK_ACQUIRED", flush=True)
                    cursor.execute("DELETE FROM mart.fitness_leads_funnel_task_service")
                    cursor.execute("DELETE FROM mart.fitness_leads_funnel_task")
                    print("TARGET_DELETE_COMPLETE", flush=True)
                copy_target(cursor, "task", paths["task"], counts["task"])
                copy_target(cursor, "task_service", paths["task_service"], counts["task_service"])
                require_reconciliation(cursor, counts, controls, start, end)
                print("TARGET_COMMIT_STARTED", flush=True)
                target.commit()
                print("TARGET_COMMIT_PASS", flush=True)
        except Exception:
            target.rollback()
            print("TARGET_ROLLBACK_COMPLETE", flush=True)
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()
    if args.apply == args.rebuild:
        parser.error("choose exactly one of --apply or --rebuild")
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    print(f"BR003_HORIZON start={start} end={end}", flush=True)
    with tempfile.TemporaryDirectory(prefix="fitness_leads_funnel_") as directory:
        paths, counts, controls = copy_source(start, end, Path(directory))
        load("apply" if args.apply else "rebuild", paths, counts, controls, start, end)


if __name__ == "__main__":
    main()
