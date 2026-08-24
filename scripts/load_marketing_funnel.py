#!/usr/bin/env python3
"""Load the reviewed marketing-funnel facts atomically after Stage-3 approval."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/marketing_funnel_source_extract.sql"
DDL = ROOT / "sql/marts/marketing_funnel_reviewed_plan.sql"
RECONCILIATION = ROOT / "sql/tests/marketing_funnel_reconciliation.sql"
TARGETS = {"task": "mart.marketing_funnel_task", "task_contract": "mart.marketing_funnel_task_contract"}
COLUMNS = {
    "task": """task_id, task_code, task_created_at, task_date, closed_at, forced_closed_at,
        funnel_id, funnel_name, club_id, club_name, client_key, client_code, tenure_type,
        campaign_id, campaign_name, parent_campaign_name, unsuccessful_reason, funnel_stage_name,
        first_interaction_type_raw, first_interaction_type, traffic_direction, task_count""",
    "task_contract": """task_id, contract_id, contract_name, contract_client_key,
        contract_client_code, activation_date, is_conversion_qualified, contract_age_group,
        contract_payment_type, contract_duration_group, contract_count""",
}


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result = {"host": values["PGHOST"], "port": values["PGPORT"], "dbname": values["PGDATABASE"],
              "user": values["PGUSER"], "password": values["PGPASSWORD"], "connect_timeout": "15"}
    if sslmode := os.environ.get(prefix + "PGSSLMODE"):
        result["sslmode"] = sslmode
    return result


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
    if "CREATE TABLE mart.marketing_funnel_task" not in text:
        raise RuntimeError("Unexpected reviewed DDL")
    return text


def copy_source(start: date, end: date, directory: Path) -> tuple[dict[str, Path], dict[str, int]]:
    paths, counts = {}, {}
    with psycopg.connect(**config("SOURCE_")) as source:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            for ordinal, name in enumerate(("task", "task_contract"), 1):
                path = directory / f"{ordinal:02d}_{name}.copy"
                with path.open("wb") as output, cursor.copy(
                    f"COPY ({render_extract(sections()[name], start, end)}) TO STDOUT WITH (FORMAT BINARY)"
                ) as copy:
                    while block := copy.read():
                        output.write(block)
                paths[name], counts[name] = path, cursor.rowcount
                print(f"SOURCE_COPY_READY name={name} rows={cursor.rowcount}", flush=True)
            source.rollback()
    return paths, counts


def relation_names(cursor) -> set[str]:
    cursor.execute("""SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                      WHERE n.nspname='mart' AND c.relname IN ('marketing_funnel_task', 'marketing_funnel_task_contract')""")
    return {row[0] for row in cursor}


def copy_target(cursor, name: str, path: Path, expected: int) -> None:
    columns = " ".join(COLUMNS[name].split())
    with cursor.copy(f"COPY {TARGETS[name]} ({columns}) FROM STDIN WITH (FORMAT BINARY)") as copy:
        with path.open("rb") as source:
            while block := source.read(1_048_576):
                copy.write(block)
    if cursor.rowcount != expected:
        raise RuntimeError(f"COPY total differs for {name}: {cursor.rowcount} != {expected}")


def reconciliation_statements(task_rows: int, contract_rows: int, start: date, end: date) -> list[str]:
    text = RECONCILIATION.read_text(encoding="utf-8")
    text = (text.replace("$1::bigint", str(task_rows)).replace("$2::bigint", str(contract_rows))
            .replace("$3::date", f"DATE '{start}'").replace("$4::date", f"DATE '{end}'"))
    return [part.strip().rstrip(";")
            for part in re.split(r"(?m)(?=-- MF-R\d+)", text)
            if part.strip().startswith("-- MF-R")]


def require_reconciliation(cursor, counts: dict[str, int], start: date, end: date) -> None:
    statements = reconciliation_statements(counts["task"], counts["task_contract"], start, end)
    if len(statements) != 6:
        raise RuntimeError(f"Unexpected reconciliation statement count: {len(statements)}")
    rows = []
    for statement in statements:
        cursor.execute(statement)
        rows.append(cursor.fetchone())
    if not rows[0][-1] or any(rows[1]) or any(rows[2]) or any(rows[3]) or not rows[4][-1] or rows[5][0] != 0:
        raise RuntimeError(f"Reconciliation failed: {rows}")
    print("RECONCILIATION_PASS MF-R01—MF-R06", flush=True)


def load(mode: str, paths: dict[str, Path], counts: dict[str, int], start: date, end: date) -> None:
    expected = {"marketing_funnel_task", "marketing_funnel_task_contract"}
    with psycopg.connect(**config("TARGET_")) as target:
        try:
            with target.cursor() as cursor:
                cursor.execute("BEGIN")
                found = relation_names(cursor)
                if mode == "apply":
                    if found:
                        raise RuntimeError(f"Initial DDL requires absent targets, found: {sorted(found)}")
                    cursor.execute(ddl_without_transaction())
                elif found != expected:
                    raise RuntimeError(f"Rebuild requires both targets, found: {sorted(found)}")
                else:
                    cursor.execute("LOCK TABLE mart.marketing_funnel_task_contract, mart.marketing_funnel_task IN ACCESS EXCLUSIVE MODE")
                    cursor.execute("DELETE FROM mart.marketing_funnel_task_contract")
                    cursor.execute("DELETE FROM mart.marketing_funnel_task")
                copy_target(cursor, "task", paths["task"], counts["task"])
                copy_target(cursor, "task_contract", paths["task_contract"], counts["task_contract"])
                require_reconciliation(cursor, counts, start, end)
                target.commit()
        except Exception:
            target.rollback()
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
    with tempfile.TemporaryDirectory(prefix="marketing_funnel_") as directory:
        paths, counts = copy_source(start, end, Path(directory))
        load("apply" if args.apply else "rebuild", paths, counts, start, end)


if __name__ == "__main__":
    main()
