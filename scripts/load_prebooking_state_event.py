#!/usr/bin/env python3
"""Atomically rebuild mart.prebooking_state_event from one 1C snapshot."""
from __future__ import annotations

import argparse
import os
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/prebooking_state_event_extract.sql"
COLUMNS = """state_event_at, booking_kind, recorder_tref, recorder_id, source_line_no,
legacy_settlement_line_no, booking_document_id, lesson_start_at, lesson_end_at,
club_id, activity_id, employee_id, service_id, client_key, client_code, client_name,
state_order, event_category, booking_delta, cancelled_before_lesson, is_paid_booking""".replace("\n", " ")

def config(prefix: str) -> dict[str, str]:
    keys = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {key: os.environ.get(prefix + key) for key in keys}
    missing = [prefix + key for key, value in values.items() if not value]
    if missing: raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {"host": values["PGHOST"], "port": values["PGPORT"], "dbname": values["PGDATABASE"], "user": values["PGUSER"], "password": values["PGPASSWORD"]}
    if prefix == "SOURCE_" and os.environ.get("SOURCE_PGSSLMODE"): result["sslmode"] = os.environ["SOURCE_PGSSLMODE"]
    return result

def br003_horizon(today: date) -> tuple[date, date]:
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date(today.year + 1, 1, 1)

def extract_sql(start: date, end: date) -> str:
    sql = EXTRACT.read_text(encoding="utf-8")
    return sql[sql.index("WITH pz AS ("):].strip().rstrip(";").replace("$1::date", f"DATE '{start.isoformat()}'").replace("$2::date", f"DATE '{end.isoformat()}'")

def controls(cursor, relation: str) -> tuple[int, int, int, int, int]:
    cursor.execute(f"""SELECT count(*)::bigint, coalesce(sum(booking_delta),0)::bigint,
        count(*) FILTER (WHERE booking_kind='PZ')::bigint,
        count(*) FILTER (WHERE booking_kind='GZ')::bigint,
        count(*) FILTER (WHERE state_order=4)::bigint FROM {relation}""")
    return cursor.fetchone()

def require_stage_integrity(cursor) -> None:
    cursor.execute("""SELECT count(*) FROM (SELECT 1 FROM _prebooking_state_event_stage
        GROUP BY booking_kind, recorder_tref, recorder_id, source_line_no, legacy_settlement_line_no HAVING count(*) > 1) d""")
    if cursor.fetchone()[0]: raise RuntimeError("Duplicate legacy logical key in source stage")
    cursor.execute("""SELECT count(*) FROM _prebooking_state_event_stage WHERE state_event_at IS NULL OR booking_kind IS NULL OR recorder_tref IS NULL OR recorder_id IS NULL OR source_line_no IS NULL OR booking_document_id IS NULL OR lesson_start_at IS NULL OR lesson_end_at IS NULL OR club_id IS NULL OR employee_id IS NULL OR service_id IS NULL OR client_key IS NULL OR client_name IS NULL OR state_order IS NULL OR event_category IS NULL OR booking_delta IS NULL OR is_paid_booking IS NULL""")
    if cursor.fetchone()[0]: raise RuntimeError("Fact-contract violation in source stage")

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--apply", action="store_true", help="perform approved target DML")
    if not parser.parse_args().apply: raise SystemExit("Refusing DML without --apply")
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date()); query = extract_sql(start, end)
    with psycopg.connect(**config("SOURCE_")) as source, psycopg.connect(**config("MART_")) as target:
        with source.cursor() as s, target.cursor() as t:
            s.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            expected = controls(s, f"({query}) q")
            if not expected[0]: raise RuntimeError("Unexpected empty source projection")
            print(f"SOURCE_SNAPSHOT horizon={start}..{end} rows={expected[0]} booking_delta={expected[1]} pz_rows={expected[2]} gz_rows={expected[3]} arrived_rows={expected[4]}", flush=True)
            t.execute("BEGIN"); t.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.prebooking_state_event:refresh",))
            t.execute("CREATE TEMP TABLE _prebooking_state_event_stage (LIKE mart.prebooking_state_event INCLUDING DEFAULTS) ON COMMIT DROP")
            with t.copy(f"COPY _prebooking_state_event_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as tc, s.copy(f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)") as sc:
                for block in sc: tc.write(block)
            require_stage_integrity(t); stage = controls(t, "_prebooking_state_event_stage")
            if stage != expected: raise RuntimeError("Staging controls differ from the source snapshot")
            print(f"STAGE_PASS rows={stage[0]} booking_delta={stage[1]} pz_rows={stage[2]} gz_rows={stage[3]} arrived_rows={stage[4]} duplicate_keys=0 contract_violations=0", flush=True)
            t.execute("DELETE FROM mart.prebooking_state_event")
            t.execute(f"INSERT INTO mart.prebooking_state_event ({COLUMNS}) SELECT {COLUMNS} FROM _prebooking_state_event_stage")
            persisted = controls(t, "mart.prebooking_state_event")
            if persisted != stage: raise RuntimeError("Persistent fact controls differ from the source snapshot")
            target.commit(); print(f"DML_COMMITTED rows={persisted[0]} booking_delta={persisted[1]}", flush=True); source.rollback()

if __name__ == "__main__": main()
