#!/usr/bin/env python3
"""Guarded future loader for mart.fitness_funnel_client_outcome.

This file is reviewed in technical SQL review only.  It must not be run until
an independent physical-admission package supplies the exact token and cap.
"""
from __future__ import annotations

import argparse
import os
import sys
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.load_children_package_sale import config
from scripts.mart_connection import connect_with_retry

EXTRACT = ROOT / "sql/marts/fitness_funnel_client_outcome_source_extract.sql"
CONTROLS = ROOT / "sql/marts/fitness_funnel_client_outcome_source_controls.sql"
DDL = ROOT / "sql/marts/fitness_funnel_client_outcome_ddl.sql"
RECON = ROOT / "sql/tests/fitness_funnel_client_outcome_reconciliation.sql"
TABLE = "mart.fitness_funnel_client_outcome"
STAGE = "_fitness_funnel_client_outcome_stage"
COLUMNS = "outcome_source_key,client_key,outcome_date,outcome_type,club_id,service_id,employee_id,outcome_count"
TOKEN = "FFCOUTCOME_PHYSICAL_ADMISSION_REQUIRED"
OPTIONS = {"connect_timeout": 15, "keepalives": 1, "keepalives_idle": 60,
           "keepalives_interval": 15, "keepalives_count": 4, "tcp_user_timeout": 180_000}


def source_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(lambda: psycopg.connect(**(config("SOURCE_") | OPTIONS | {"application_name": name})), endpoint="source")


def target_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(lambda: psycopg.connect(**(config("MART_") | OPTIONS | {"application_name": name})), endpoint="mart")


def render(path: Path, start: date, end: date) -> str:
    return (path.read_text(encoding="utf-8").strip().rstrip(";")
            .replace("$1::date", f"DATE '{start.isoformat()}'")
            .replace("$2::date", f"DATE '{end.isoformat()}'"))


def statements(path: Path) -> list[str]:
    return [part.strip() for part in "\n".join(line for line in path.read_text(encoding="utf-8").splitlines()
                                                 if not line.lstrip().startswith("--")).split(";") if part.strip()]


def source_contract(cursor: psycopg.Cursor, start: date, end: date) -> None:
    results = []
    for sql in statements(CONTROLS):
        cursor.execute(sql.replace("$1::date", f"DATE '{start.isoformat()}'").replace("$2::date", f"DATE '{end.isoformat()}'"))
        results.append(dict(zip((c.name for c in cursor.description), cursor.fetchone(), strict=True)))
    first, second = results
    if any(int(first[k]) != 0 for k in ("duplicate_source_keys", "required_null_rows", "horizon_rows")):
        raise RuntimeError(f"FF-O01 failed: {first}")
    if int(second["duplicate_physical_keys"]) != 0:
        raise RuntimeError(f"FF-O02 failed: {second}")


def export_snapshot(start: date, end: date, cap: int) -> tuple[Path, int]:
    descriptor, raw_path = tempfile.mkstemp(prefix="fitness_funnel_outcome_", suffix=".copy")
    os.close(descriptor)
    path = Path(raw_path)
    try:
        with source_connection("fitness_funnel_outcome_source") as conn, conn.cursor() as cur:
            cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cur.execute("SET LOCAL statement_timeout='300s'")
            cur.execute("SET LOCAL work_mem='64MB'")
            source_contract(cur, start, end)
            extract = render(EXTRACT, start, end)
            cur.execute(f"SELECT count(*) FROM ({extract}) q")
            expected = int(cur.fetchone()[0])
            with path.open("wb") as output, cur.copy(f"COPY ({extract}) TO STDOUT (FORMAT BINARY)") as copy:
                for block in copy:
                    output.write(block)
                    if output.tell() > cap:
                        raise RuntimeError("derived COPY file exceeds separately approved cap")
            cur.execute("ROLLBACK")
        return path, expected
    except Exception:
        path.unlink(missing_ok=True)
        raise


def load_atomic(path: Path, expected: int, start: date, end: date) -> None:
    with target_connection("fitness_funnel_outcome_target") as conn, conn.cursor() as cur:
        with conn.transaction():
            cur.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TABLE,))
            cur.execute("SELECT to_regclass(%s)", (TABLE,))
            if cur.fetchone()[0] is None:
                for sql in statements(DDL): cur.execute(sql)
            cur.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
            with path.open("rb") as source, cur.copy(f"COPY {STAGE} ({COLUMNS}) FROM STDIN (FORMAT BINARY)") as copy:
                while block := source.read(1024 * 1024): copy.write(block)
            cur.execute(f"DELETE FROM {TABLE}")
            cur.execute(f"INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM {STAGE}")
            sql = (RECON.read_text(encoding="utf-8").strip().rstrip(";")
                   .replace("$1", str(expected)).replace("$2::date", f"DATE '{start.isoformat()}'").replace("$3::date", f"DATE '{end.isoformat()}'"))
            cur.execute(sql)
            failures = [row for row in cur.fetchall() if row[3] != "PASS"]
            if failures: raise RuntimeError(f"target reconciliation failed: {failures}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--admission-token", required=True)
    parser.add_argument("--start", type=date.fromisoformat, default=date(2024, 1, 1))
    parser.add_argument("--end", type=date.fromisoformat,
                        default=datetime.now(ZoneInfo("Europe/Moscow")).date() + timedelta(days=1))
    parser.add_argument("--max-derived-bytes", type=int, required=True)
    args = parser.parse_args()
    if args.admission_token != TOKEN: raise SystemExit("physical admission token required")
    if args.start >= args.end or args.max_derived_bytes <= 0: raise SystemExit("invalid horizon or cap")
    copy_path, expected = export_snapshot(args.start, args.end, args.max_derived_bytes)
    try: load_atomic(copy_path, expected, args.start, args.end)
    finally: copy_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
