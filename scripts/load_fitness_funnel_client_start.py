#!/usr/bin/env python3
"""Future atomic delivery runner for mart.fitness_funnel_client_start.

This runner is deliberately guarded: it is executable only by a separately
approved physical-admission package.  The present technical-review package
does not invoke it.
"""
from __future__ import annotations

import argparse
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.load_children_package_sale import config
from scripts.mart_connection import connect_with_retry


EXTRACT = ROOT / "sql/marts/fitness_funnel_client_start_source_extract.sql"
CONTROLS = ROOT / "sql/marts/fitness_funnel_client_start_source_controls.sql"
DDL = ROOT / "sql/marts/fitness_funnel_client_start_ddl.sql"
RECONCILIATION = ROOT / "sql/tests/fitness_funnel_client_start_reconciliation.sql"
TABLE = "mart.fitness_funnel_client_start"
STAGE = "_fitness_funnel_client_start_stage"
COLUMNS = "client_key,membership_start_date,access_club_id,tenure_type,client_count"
CONNECTION_OPTIONS = {
    "connect_timeout": 15,
    "keepalives": 1,
    "keepalives_idle": 60,
    "keepalives_interval": 15,
    "keepalives_count": 4,
    "tcp_user_timeout": 180_000,
}
ADMISSION_TOKEN = "FFCSTART_PHYSICAL_ADMISSION_REQUIRED"


def source_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(
        lambda: psycopg.connect(**(config("SOURCE_") | CONNECTION_OPTIONS | {"application_name": name})),
        endpoint="source",
    )


def target_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(
        lambda: psycopg.connect(**(config("MART_") | CONNECTION_OPTIONS | {"application_name": name})),
        endpoint="mart",
    )


def render(path: Path, start: date, end: date) -> str:
    text = path.read_text(encoding="utf-8").strip().rstrip(";")
    return (text.replace("$1::date", f"DATE '{start.isoformat()}'")
                .replace("$2::date", f"DATE '{end.isoformat()}'"))


def statements(path: Path) -> list[str]:
    body = "\n".join(
        line for line in path.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("--")
    )
    return [statement.strip() for statement in body.split(";") if statement.strip()]


def execute_ddl(cursor: psycopg.Cursor) -> None:
    for statement in statements(DDL):
        cursor.execute(statement)


def source_controls(cursor: psycopg.Cursor, start: date, end: date) -> dict[str, dict[str, object]]:
    results: dict[str, dict[str, object]] = {}
    for statement in statements(CONTROLS):
        cursor.execute(statement.replace("$1::date", f"DATE '{start.isoformat()}'")
                             .replace("$2::date", f"DATE '{end.isoformat()}'"))
        row = cursor.fetchone()
        values = dict(zip((column.name for column in cursor.description), row, strict=True))
        results[str(values["control_id"])] = values
    s01, s02, s03 = results["FF-S01"], results["FF-S02"], results["FF-S03"]
    if any(int(s01[name]) != 0 for name in ("duplicate_contract_ref_rows", "client_orphan_rows", "club_orphan_rows")):
        raise RuntimeError(f"FF-S01 failed: {s01}")
    if any(int(s02[name]) != 0 for name in ("invalid_selected_rows", "duplicate_selected_key_rows")):
        raise RuntimeError(f"FF-S02 selector failed: {s02}")
    if any(int(s03[name]) != 0 for name in ("required_null_rows", "future_start_rows", "duplicate_target_key_rows")):
        raise RuntimeError(f"FF-S03 failed: {s03}")
    return results


def export_derived_snapshot(start: date, end: date, max_bytes: int) -> tuple[Path, dict[str, dict[str, object]]]:
    """Create one derived binary COPY file; any source failure removes it."""
    for attempt in range(1, 4):
        temporary = tempfile.NamedTemporaryFile(prefix="fitness_funnel_client_start_", suffix=".copy", delete=False)
        path = Path(temporary.name)
        try:
            with source_connection("fitness_funnel_client_start_source") as source, source.cursor() as cursor:
                cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                cursor.execute("SET LOCAL statement_timeout = '300s'")
                # Measured on the exact full extract: prevents the final sort
                # from spilling while remaining scoped to this read-only session.
                cursor.execute("SET LOCAL work_mem = '64MB'")
                controls = source_controls(cursor, start, end)
                with cursor.copy(f"COPY ({render(EXTRACT, start, end)}) TO STDOUT (FORMAT BINARY)") as copy:
                    for block in copy:
                        temporary.write(block)
                        if temporary.tell() > max_bytes:
                            raise RuntimeError("derived COPY file exceeds the separately measured admission cap")
                cursor.execute("ROLLBACK")
            temporary.close()
            return path, controls
        except psycopg.OperationalError:
            temporary.close()
            path.unlink(missing_ok=True)
            if attempt == 3:
                raise
        except Exception:
            temporary.close()
            path.unlink(missing_ok=True)
            raise
    raise AssertionError("unreachable")


def reconciliation_sql(expected: dict[str, object]) -> str:
    required = ("target_candidate_rows", "min_membership_start_date", "max_membership_start_date")
    if any(expected[name] is None for name in required):
        raise RuntimeError("FF-S03 expected values are incomplete")
    sql = RECONCILIATION.read_text(encoding="utf-8").strip().rstrip(";")
    return (sql.replace("$1::text", f"'{int(expected['target_candidate_rows'])}'::text")
               .replace("$2::text", f"DATE '{expected['min_membership_start_date']}'::text")
               .replace("$3::text", f"DATE '{expected['max_membership_start_date']}'::text"))


def load_atomic(copy_path: Path, controls: dict[str, dict[str, object]]) -> None:
    with target_connection("fitness_funnel_client_start_target") as target, target.cursor() as cursor:
        with target.transaction():
            cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TABLE,))
            cursor.execute("SELECT to_regclass(%s)", (TABLE,))
            if cursor.fetchone()[0] is None:
                execute_ddl(cursor)
            cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
            with cursor.copy(f"COPY {STAGE} ({COLUMNS}) FROM STDIN (FORMAT BINARY)") as copy, copy_path.open("rb") as source_file:
                while block := source_file.read(1024 * 1024):
                    copy.write(block)
            cursor.execute(f"DELETE FROM {TABLE}")
            cursor.execute(f"INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM {STAGE}")
            cursor.execute(reconciliation_sql(controls["FF-S03"]))
            failures = [dict(zip((item.name for item in cursor.description), row, strict=True)) for row in cursor.fetchall()
                        if row[4] != "PASS"]
            if failures:
                raise RuntimeError(f"target reconciliation failed: {failures}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--admission-token", required=True)
    parser.add_argument("--start", type=date.fromisoformat, default=date(2024, 1, 1))
    parser.add_argument("--end", type=date.fromisoformat,
                        default=lambda: datetime.now(ZoneInfo("Europe/Moscow")).date())
    parser.add_argument("--max-derived-bytes", type=int, required=True)
    args = parser.parse_args()
    if args.admission_token != ADMISSION_TOKEN:
        raise SystemExit("refusing target DDL/DML without the physical-admission token")
    end = args.end() if callable(args.end) else args.end
    if args.start >= end or args.max_derived_bytes <= 0:
        raise SystemExit("start/end range and derived COPY cap must be positive")
    copy_path, controls = export_derived_snapshot(args.start, end, args.max_derived_bytes)
    try:
        load_atomic(copy_path, controls)
    finally:
        copy_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
