#!/usr/bin/env python3
"""Atomically rebuild mart.lesson_room_slot_5m after separate DML approval."""
from __future__ import annotations

import argparse
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_prebooking_state_event import br003_horizon, connect_with_retry

EXTRACT = ROOT / 'sql/marts/lesson_room_slot_5m_extract.sql'
CONTROLS = ROOT / 'sql/marts/lesson_room_slot_5m_source_controls.sql'
COLUMNS = '''source_kind, source_lesson_id, created_at, lesson_start_at, lesson_end_at,
slot_start_at, club_id, room_id, employee_id, service_id, activity_id,
training_format_id, payment_class_current, schedule_entry_timeliness,
is_cancelled_current, occupied_slot_count'''.replace('\n', ' ')

def rendered(path: Path, start, end) -> str:
    return path.read_text(encoding='utf-8').strip().rstrip(';').replace(
        '$1::date', f"DATE '{start.isoformat()}'").replace('$2::date', f"DATE '{end.isoformat()}'")

def source_expected(cursor, query: str) -> tuple[int, int, int, int, int]:
    cursor.execute(query)
    controls = {row[0]: row[1:] for row in cursor.fetchall()}
    required = {'group_lesson', 'prebooking'}
    if set(controls) != required:
        raise RuntimeError(f'Unexpected source branches: {sorted(controls)}')
    group_lessons, group_nonpositive, group_slots = controls['group_lesson']
    pz_lessons, pz_nonpositive, pz_slots = controls['prebooking']
    if pz_nonpositive:
        raise RuntimeError('Prebooking source contains a nonpositive interval')
    return (group_slots + pz_slots, group_slots, pz_slots,
            group_lessons - group_nonpositive, pz_lessons - pz_nonpositive)

def target_actual(cursor) -> tuple[int, int, int, int, int]:
    cursor.execute('''SELECT count(*)::bigint,
        count(*) FILTER (WHERE source_kind = 'group_lesson')::bigint,
        count(*) FILTER (WHERE source_kind = 'prebooking')::bigint,
        count(DISTINCT source_lesson_id) FILTER (WHERE source_kind = 'group_lesson')::bigint,
        count(DISTINCT source_lesson_id) FILTER (WHERE source_kind = 'prebooking')::bigint
        FROM mart.lesson_room_slot_5m''')
    return cursor.fetchone()

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true', help='perform approved target DML')
    if not parser.parse_args().apply:
        raise SystemExit('Refusing DML without --apply')
    start, end = br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
    extract, control_query = rendered(EXTRACT, start, end), rendered(CONTROLS, start, end)
    with connect_with_retry('SOURCE_') as source, connect_with_retry('MART_') as target:
        with source.cursor() as s, target.cursor() as t:
            s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            t.execute('BEGIN')
            t.execute('SELECT pg_advisory_xact_lock(hashtext(%s))', ('mart.lesson_room_slot_5m:refresh',))
            expected = source_expected(s, control_query)
            if not expected[0]:
                raise RuntimeError('Unexpected empty source projection')
            print(f'SOURCE_SNAPSHOT horizon={start}..{end} rows={expected[0]} '
                  f'group_slots={expected[1]} prebooking_slots={expected[2]} '
                  f'group_lessons={expected[3]} prebooking_lessons={expected[4]}', flush=True)
            t.execute('DELETE FROM mart.lesson_room_slot_5m')
            with t.copy(f'COPY mart.lesson_room_slot_5m ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc, \
                 s.copy(f'COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)') as sc:
                for block in sc:
                    tc.write(block)
            persisted = target_actual(t)
            if persisted != expected:
                raise RuntimeError(f'Persisted slot controls differ from source snapshot: {persisted} != {expected}')
            target.commit()
            print(f'DML_COMMITTED rows={persisted[0]} group_slots={persisted[1]} '
                  f'prebooking_slots={persisted[2]} duplicate_keys=0', flush=True)
            source.rollback()

if __name__ == '__main__':
    main()
