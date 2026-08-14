#!/usr/bin/env python3
"""Atomically rebuild mart.group_lesson from a 1C base and shared state fact."""
from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from scripts.load_prebooking_state_event import br003_horizon, connect_with_retry

ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/group_lesson_source_extract.sql"
CONTROLS = ROOT / "sql/marts/group_lesson_source_controls.sql"
COLUMNS = """group_lesson_id, lesson_created_at, lesson_start_at, lesson_end_at,
club_id, activity_id, employee_id, service_id, capacity, is_free_program,
free_program_arrived_count""".replace("\n", " ")

def rendered(path: Path, start, end) -> str:
    return path.read_text(encoding="utf-8").strip().rstrip(";").replace(
        "$1::date", f"DATE '{start.isoformat()}'").replace("$2::date", f"DATE '{end.isoformat()}'")

def base_controls(cursor, query: str) -> tuple[int, int, int]:
    cursor.execute(query)
    return cursor.fetchone()

def target_controls(cursor) -> tuple[int, int, int]:
    cursor.execute("""SELECT count(*)::bigint, coalesce(sum(capacity), 0)::bigint,
        coalesce(sum(free_program_arrived_count), 0)::bigint
        FROM mart.group_lesson""")
    return cursor.fetchone()

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform approved target DML")
    if not parser.parse_args().apply:
        raise SystemExit("Refusing DML without --apply")
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    extract, control_query = rendered(EXTRACT, start, end), rendered(CONTROLS, start, end)
    with connect_with_retry("SOURCE_") as source, connect_with_retry("MART_") as target:
        with source.cursor() as s, target.cursor() as t:
            s.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            t.execute("BEGIN")
            t.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.group_lesson:refresh",))
            t.execute("""CREATE TEMP TABLE _group_lesson_source_stage (
                group_lesson_id text NOT NULL, lesson_created_at timestamp NOT NULL,
                lesson_start_at timestamp NOT NULL, lesson_end_at timestamp NOT NULL,
                club_id text NOT NULL, activity_id text, employee_id text NOT NULL,
                service_id text NOT NULL, capacity integer, is_free_program boolean NOT NULL,
                free_program_arrived_count integer NOT NULL) ON COMMIT DROP""")
            expected = base_controls(s, control_query)
            if not expected[0]:
                raise RuntimeError("Unexpected empty group-lesson source projection")
            print(f"SOURCE_SNAPSHOT horizon={start}..{end} rows={expected[0]} capacity_sum={expected[1]} free_arrived_sum={expected[2]}", flush=True)
            with t.copy(f"COPY _group_lesson_source_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as tc, s.copy(f"COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)") as sc:
                for block in sc:
                    tc.write(block)
            t.execute("""SELECT count(*) FROM (SELECT 1 FROM _group_lesson_source_stage
                GROUP BY group_lesson_id HAVING count(*) > 1) d""")
            if t.fetchone()[0]:
                raise RuntimeError("Duplicate group_lesson_id in source stage")
            t.execute("SELECT count(*) FROM mart.prebooking_state_event WHERE booking_kind='GZ'")
            if not t.fetchone()[0]:
                raise RuntimeError("Required mart.prebooking_state_event GZ branch is empty")
            t.execute("DELETE FROM mart.group_lesson")
            t.execute("""WITH state_per_lesson AS (
                SELECT booking_document_id AS group_lesson_id,
                       coalesce(sum(booking_delta), 0)::bigint AS active_booking_count,
                       nullif(count(*) FILTER (WHERE state_order = 4), 0)::bigint AS paid_arrived_count
                FROM mart.prebooking_state_event WHERE booking_kind = 'GZ'
                GROUP BY booking_document_id
            ) INSERT INTO mart.group_lesson (
                group_lesson_id, lesson_created_at, lesson_start_at, lesson_end_at,
                club_id, activity_id, employee_id, service_id, capacity, is_free_program,
                active_booking_count, arrived_count, free_program_arrived_count
            ) SELECT s.group_lesson_id, s.lesson_created_at, s.lesson_start_at,
                s.lesson_end_at, s.club_id, s.activity_id, s.employee_id, s.service_id,
                s.capacity, s.is_free_program, coalesce(st.active_booking_count, 0),
                coalesce(st.paid_arrived_count, s.free_program_arrived_count, 0),
                s.free_program_arrived_count
            FROM _group_lesson_source_stage s LEFT JOIN state_per_lesson st USING (group_lesson_id)""")
            persisted = target_controls(t)
            if persisted != expected:
                raise RuntimeError("Persistent group-lesson base controls differ from source snapshot")
            target.commit()
            print(f"DML_COMMITTED rows={persisted[0]} capacity_sum={persisted[1]} free_arrived_sum={persisted[2]} duplicate_keys=0", flush=True)
            source.rollback()

if __name__ == "__main__":
    main()
