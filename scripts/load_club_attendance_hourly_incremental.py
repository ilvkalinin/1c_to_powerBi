#!/usr/bin/env python3
"""Refresh source-different visit dates without invoking the full loader."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_club_attendance_hourly import COLUMNS, EXTRACT, TARGET, br003_horizon, config, render, sections
from scripts.mart_connection import connect_with_retry

DEFAULT_CONFIG = ROOT / 'config/club_attendance_hourly_incremental.json'
SOURCE_FINGERPRINT = ROOT / 'sql/marts/club_attendance_hourly_incremental_source_fingerprint.sql'
TARGET_FINGERPRINT = ROOT / 'sql/marts/club_attendance_hourly_incremental_target_fingerprint.sql'
TARGET_REPLACE = ROOT / 'sql/marts/club_attendance_hourly_incremental_target_replace.sql'
MARKER = '/*__CLUB_ATTENDANCE_HOURLY_FACT__*/'
STAGE = '_club_attendance_hourly_incremental_stage'


def rendered(path: Path, start: date, end: date) -> str:
    return path.read_text(encoding='utf-8').strip().rstrip(';').replace('$1::date', f"DATE '{start}'").replace('$2::date', f"DATE '{end}'")


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding='utf-8'))
    expected = {'object': TARGET, 'mode': 'target_fingerprint_diff', 'timezone': 'Europe/Moscow',
                'change_detection': 'source_target_double_md5_by_visit_date',
                'changed_date_policy': 'replace_contiguous_min_to_max',
                'deletion_policy': 'detected_as_source_target_fingerprint_difference',
                'no_change_policy': 'no_target_dml'}
    if any(payload.get(key) != value for key, value in expected.items()):
        raise RuntimeError('Unexpected incremental config')
    if payload.get('watermark') is not None or payload.get('incremental_sla') is not None:
        raise RuntimeError('Unvalidated watermark or incremental SLA is forbidden')


def source_query(start: date, end: date) -> str:
    return render(sections()['hourly'], start, end)


def source_fingerprint_query(start: date, end: date) -> str:
    template = SOURCE_FINGERPRINT.read_text(encoding='utf-8')
    if template.count(MARKER) != 1:
        raise RuntimeError('Unexpected source fingerprint marker')
    return template.replace(MARKER, source_query(start, end))


def fingerprints(cursor, query: str) -> dict[date, tuple[int, str, str]]:
    cursor.execute(query)
    return {day: (int(rows), first, second) for day, rows, first, second in cursor}


def changed_dates(source: dict[date, tuple[int, str, str]], target: dict[date, tuple[int, str, str]]) -> list[date]:
    return sorted(day for day in set(source) | set(target) if source.get(day) != target.get(day))


def source_controls(cursor, query: str) -> tuple[int, int, Decimal]:
    cursor.execute('SELECT count(*)::bigint, coalesce(sum(visit_count), 0)::bigint, round(coalesce(sum(club_minutes_total), 0)::numeric, 6) FROM (' + query + ') AS fact')
    rows, visits, minutes = cursor.fetchone()
    return int(rows), int(visits), Decimal(minutes)


def require_stage(cursor, start: date, end: date) -> None:
    cursor.execute(f'''SELECT count(*) FROM (SELECT 1 FROM {STAGE} GROUP BY visit_date, club_id, start_hour, end_hour, sex_code, age_years HAVING count(*) > 1) AS duplicates''')
    if cursor.fetchone()[0]:
        raise RuntimeError('Incremental stage has duplicate logical keys')
    cursor.execute(f'''SELECT count(*) FROM {STAGE} WHERE visit_date < %s OR visit_date >= %s OR club_id IS NULL OR btrim(club_id) = '' OR start_hour NOT BETWEEN 0 AND 23 OR (end_hour IS NOT NULL AND end_hour NOT BETWEEN 0 AND 23) OR visit_count <= 0''', (start, end))
    if cursor.fetchone()[0]:
        raise RuntimeError('Incremental stage violates the fact contract')


def target_controls(cursor, relation: str, start: date, end: date) -> tuple[int, int, Decimal]:
    cursor.execute(f'SELECT count(*)::bigint, coalesce(sum(visit_count), 0)::bigint, round(coalesce(sum(club_minutes_total), 0)::numeric, 6) FROM {relation} WHERE visit_date >= %s AND visit_date < %s', (start, end))
    rows, visits, minutes = cursor.fetchone()
    return int(rows), int(visits), Decimal(minutes)


def copy_source(cursor, query: str, path: Path) -> int:
    with path.open('wb') as output, cursor.copy(f'COPY ({query}) TO STDOUT WITH (FORMAT BINARY)') as copied:
        for block in copied:
            output.write(block)
    return cursor.rowcount


def check_only(start: date, end: date) -> None:
    """Run the full diff without opening a target write transaction."""
    source = connect_with_retry(lambda: psycopg.connect(**config('SOURCE_')), endpoint='source')
    target = connect_with_retry(lambda: psycopg.connect(**config('MART_')), endpoint='mart')
    try:
        with source.cursor() as source_cursor, target.cursor() as target_cursor:
            source_cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            source_cursor.execute("SET LOCAL statement_timeout = '900000'")
            source_cursor.execute('SET LOCAL enable_hashjoin = off')
            target_cursor.execute('BEGIN READ ONLY')
            source_digest = fingerprints(source_cursor, source_fingerprint_query(start, end))
            target_digest = fingerprints(target_cursor, rendered(TARGET_FINGERPRINT, start, end))
            dates = changed_dates(source_digest, target_digest)
        source.rollback(); target.rollback()
        print(f'CHECK_ONLY source_dates={len(source_digest)} changed_dates={len(dates)}', flush=True)
        if dates:
            print(f'CHECK_ONLY_WINDOW start={dates[0]} end={date.fromordinal(dates[-1].toordinal() + 1)}', flush=True)
    finally:
        source.close(); target.close()


def run_refresh(start: date, end: date) -> None:
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='club_attendance_hourly_incremental_') as directory:
        transfer = Path(directory) / 'affected.copy'
        source = connect_with_retry(lambda: psycopg.connect(**config('SOURCE_')), endpoint='source')
        target = connect_with_retry(lambda: psycopg.connect(**config('MART_')), endpoint='mart')
        try:
            with source.cursor() as source_cursor, target.cursor() as target_cursor:
                source_cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
                source_cursor.execute("SET LOCAL statement_timeout = '180000'")
                source_cursor.execute('SET LOCAL enable_hashjoin = off')
                source_digest = fingerprints(source_cursor, source_fingerprint_query(start, end))
                target_cursor.execute('BEGIN')
                target_cursor.execute("SET LOCAL lock_timeout = '60s'")
                target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (f'{TARGET}:incremental',))
                target_cursor.execute('SELECT to_regclass(%s)', (TARGET,))
                if target_cursor.fetchone()[0] is None:
                    raise RuntimeError('Incremental refresh requires the existing target')
                target_digest = fingerprints(target_cursor, rendered(TARGET_FINGERPRINT, start, end))
                dates = changed_dates(source_digest, target_digest)
                print(f'SOURCE_FINGERPRINT source_dates={len(source_digest)} changed_dates={len(dates)}', flush=True)
                if not dates:
                    target.commit(); source.rollback()
                    print(f'NO_CHANGES elapsed_seconds={time.monotonic() - started:.3f}', flush=True)
                    return
                affected_start, affected_end = dates[0], date.fromordinal(dates[-1].toordinal() + 1)
                query = source_query(affected_start, affected_end)
                expected = source_controls(source_cursor, query)
                source_rows = copy_source(source_cursor, query, transfer)
                if source_rows != expected[0]:
                    raise RuntimeError(f'Source COPY count differs: {source_rows} != {expected[0]}')
                target_cursor.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
                if source_rows:
                    with target_cursor.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as copied, transfer.open('rb') as input_file:
                        while block := input_file.read(1_048_576):
                            copied.write(block)
                    if target_cursor.rowcount != source_rows:
                        raise RuntimeError('Target COPY count differs from source')
                require_stage(target_cursor, affected_start, affected_end)
                if target_controls(target_cursor, STAGE, affected_start, affected_end) != expected:
                    raise RuntimeError('Stage differs from source controls')
                replacement = [item.strip() for item in rendered(TARGET_REPLACE, affected_start, affected_end).split(';') if item.strip()]
                if len(replacement) != 2:
                    raise RuntimeError('Unexpected target replacement statement count')
                for statement in replacement:
                    target_cursor.execute(statement)
                if target_controls(target_cursor, TARGET, affected_start, affected_end) != expected:
                    raise RuntimeError('Persisted target differs from source controls')
                persisted = fingerprints(target_cursor, rendered(TARGET_FINGERPRINT, start, end))
                if changed_dates(source_digest, persisted):
                    raise RuntimeError('Pre-commit source/target fingerprint mismatch')
                target.commit(); source.rollback()
                print(f'TARGET_COMMIT changed_dates={len(dates)} window={affected_start}..{affected_end} rows={source_rows} elapsed_seconds={time.monotonic() - started:.3f}', flush=True)
        except Exception:
            target.rollback(); source.rollback(); raise
        finally:
            source.close(); target.close(); transfer.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--plan-only', action='store_true')
    mode.add_argument('--check-only', action='store_true')
    mode.add_argument('--run', action='store_true')
    args = parser.parse_args()
    load_config(args.config)
    start, end = br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
    print(f'CONFIG object={TARGET} horizon={start}..{end} mode=target_fingerprint_diff', flush=True)
    if args.plan_only:
        source = connect_with_retry(lambda: psycopg.connect(**config('SOURCE_')), endpoint='source')
        try:
            with source.cursor() as cursor:
                cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
                cursor.execute("SET LOCAL statement_timeout = '900000'")
                cursor.execute('SET LOCAL enable_hashjoin = off')
                cursor.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + source_fingerprint_query(start, end))
                plan = cursor.fetchone()[0][0]
            source.rollback()
            node = plan['Plan']
            print('SOURCE_PLAN ' + json.dumps({'rows': int(node.get('Actual Rows', 0)), 'execution_ms': float(plan['Execution Time']), 'shared_hit': int(node.get('Shared Hit Blocks', 0)), 'shared_read': int(node.get('Shared Read Blocks', 0)), 'temp_read': int(node.get('Temp Read Blocks', 0)), 'temp_written': int(node.get('Temp Written Blocks', 0))}, sort_keys=True), flush=True)
        finally:
            source.close()
    elif args.check_only:
        check_only(start, end)
    else:
        run_refresh(start, end)


if __name__ == '__main__':
    main()
