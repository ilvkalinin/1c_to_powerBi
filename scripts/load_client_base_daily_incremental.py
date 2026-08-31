#!/usr/bin/env python3
"""Refresh only source-different dates of mart.client_base_daily.

This is a separate runner. It never invokes or modifies the approved full
rebuild runner. Each run computes a read-only source fingerprint for the full
BR-003 horizon, compares it with the current target, and writes only the
smallest contiguous span covering dates whose aggregate result differs.
"""

from __future__ import annotations

import argparse
import json
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

from scripts.load_client_base_daily import (
    CHILD_PACKAGE_AGE_CONTROLS,
    COLUMNS,
    EXTRACT,
    SOURCE_CONTROLS,
    br003_horizon,
    child_package_age_totals,
    config,
    copy_source_batch,
    has_br038_age_constraint,
    month_batches,
    rendered,
    require_batch_space,
    require_stage_integrity,
    reviewed_statements,
    source_scope_totals,
    source_totals,
    totals,
)
from scripts.mart_connection import connect_with_retry


DEFAULT_CONFIG = ROOT / 'config/client_base_daily_incremental.json'
SOURCE_FINGERPRINT = ROOT / 'sql/marts/client_base_daily_incremental_source_fingerprint.sql'
TARGET_FINGERPRINT = ROOT / 'sql/marts/client_base_daily_incremental_target_fingerprint.sql'
TARGET_REPLACE = ROOT / 'sql/marts/client_base_daily_incremental_target_replace.sql'
TABLE = 'mart.client_base_daily'
STAGE = '_client_base_daily_incremental_stage'
FACT_MARKER = '/*__CLIENT_BASE_DAILY_FACT__*/'


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding='utf-8'))
    expected = {
        'object': TABLE,
        'mode': 'target_fingerprint_diff',
        'timezone': 'Europe/Moscow',
        'horizon': 'br003_current',
        'change_detection': 'source_target_double_md5_by_report_date',
        'changed_date_policy': 'replace_contiguous_min_to_max',
        'deletion_policy': 'detected_as_source_target_fingerprint_difference',
        'no_change_policy': 'no_target_dml',
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise RuntimeError(f'Unexpected incremental config {key}')
    if payload.get('watermark') is not None or payload.get('incremental_sla') is not None:
        raise RuntimeError('Unvalidated watermark or incremental SLA is forbidden')


def source_fingerprint_sql(start: date, end: date) -> str:
    template = SOURCE_FINGERPRINT.read_text(encoding='utf-8')
    if template.count(FACT_MARKER) != 1:
        raise RuntimeError('Unexpected source fingerprint template marker')
    fact = rendered(EXTRACT, start, end)
    return template.replace(FACT_MARKER, fact)


def target_fingerprint_sql(start: date, end: date) -> str:
    return rendered(TARGET_FINGERPRINT, start, end)


def fingerprints(cursor, query: str) -> dict[date, tuple[int, str, str]]:
    cursor.execute(query)
    result = {
        report_date: (int(row_count), digest_v1, digest_v2)
        for report_date, row_count, digest_v1, digest_v2 in cursor
    }
    if any(not first or not second for _, first, second in result.values()):
        raise RuntimeError('Fingerprint query returned an empty digest')
    return result


def changed_dates(
    source: dict[date, tuple[int, str, str]], target: dict[date, tuple[int, str, str]],
    start: date, end: date,
) -> list[date]:
    expected = {date.fromordinal(day) for day in range(start.toordinal(), end.toordinal())}
    if set(source) != expected:
        raise RuntimeError('Source fingerprint does not cover every BR-003 date')
    return sorted(day for day in expected if source.get(day) != target.get(day))


def source_plan(start: date, end: date) -> dict[str, object]:
    source = connect_with_retry(lambda: psycopg.connect(**config('SOURCE_')), endpoint='source')
    try:
        with source.cursor() as cursor:
            cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            cursor.execute("SET LOCAL statement_timeout = '120000'")
            cursor.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + source_fingerprint_sql(start, end))
            plan = cursor.fetchone()[0][0]
        source.rollback()
        node = plan['Plan']
        return {
            'start': start.isoformat(), 'end': end.isoformat(),
            'rows': int(node.get('Actual Rows', 0)),
            'execution_ms': float(plan['Execution Time']),
            'shared_hit': int(node.get('Shared Hit Blocks', 0)),
            'shared_read': int(node.get('Shared Read Blocks', 0)),
            'temp_read': int(node.get('Temp Read Blocks', 0)),
            'temp_written': int(node.get('Temp Written Blocks', 0)),
        }
    finally:
        source.close()


def require_target_fingerprint_match(
    source: dict[date, tuple[int, str, str]], target: dict[date, tuple[int, str, str]],
    start: date, end: date, phase: str,
) -> None:
    difference = changed_dates(source, target, start, end)
    if difference:
        raise RuntimeError(f'{phase}: target fingerprint differs on {len(difference)} date(s)')


def check_only(start: date, end: date) -> None:
    """Compare the two snapshots without opening a target write transaction."""
    source = connect_with_retry(lambda: psycopg.connect(**config('SOURCE_')), endpoint='source')
    target = connect_with_retry(lambda: psycopg.connect(**config('MART_')), endpoint='mart')
    try:
        with source.cursor() as source_cursor, target.cursor() as target_cursor:
            source_cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            source_cursor.execute("SET LOCAL statement_timeout = '120000'")
            target_cursor.execute('BEGIN READ ONLY')
            source_digest = fingerprints(source_cursor, source_fingerprint_sql(start, end))
            target_digest = fingerprints(target_cursor, target_fingerprint_sql(start, end))
            dates = changed_dates(source_digest, target_digest, start, end)
        source.rollback()
        target.rollback()
        print(f'CHECK_ONLY source_dates={len(source_digest)} changed_dates={len(dates)}', flush=True)
        if dates:
            print(f'CHECK_ONLY_WINDOW start={dates[0]} end={date.fromordinal(dates[-1].toordinal() + 1)}', flush=True)
    finally:
        source.close()
        target.close()


def run_refresh(start: date, end: date) -> None:
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='client_base_daily_incremental_') as temporary_directory:
        directory = Path(temporary_directory)
        source = connect_with_retry(lambda: psycopg.connect(**config('SOURCE_')), endpoint='source')
        target = connect_with_retry(lambda: psycopg.connect(**config('MART_')), endpoint='mart')
        try:
            with source.cursor() as source_cursor:
                source_cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
                source_cursor.execute("SET LOCAL statement_timeout = '120000'")
                source_digest = fingerprints(source_cursor, source_fingerprint_sql(start, end))
            with target.cursor() as target_cursor:
                target_cursor.execute('BEGIN')
                target_cursor.execute("SET LOCAL lock_timeout = '60s'")
                target_cursor.execute("SET LOCAL idle_in_transaction_session_timeout = '240s'")
                target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (f'{TABLE}:refresh',))
                target_cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                if target_cursor.fetchone()[0] is None:
                    raise RuntimeError('Incremental refresh requires the existing target fact')
                target_digest = fingerprints(target_cursor, target_fingerprint_sql(start, end))
                dates = changed_dates(source_digest, target_digest, start, end)
                print(f'SOURCE_FINGERPRINT dates={len(source_digest)} changed_dates={len(dates)}', flush=True)
                if not dates:
                    target.commit()
                    source.rollback()
                    print(f'NO_CHANGES elapsed_seconds={time.monotonic() - started:.3f}', flush=True)
                    return

                affected_start, affected_end = dates[0], date.fromordinal(dates[-1].toordinal() + 1)
                replace = reviewed_statements(TARGET_REPLACE, affected_start, affected_end)
                if len(replace) != 2:
                    raise RuntimeError('Unexpected incremental target replacement statement count')
                with source.cursor() as source_control_cursor:
                    expected = source_totals(
                        source_control_cursor,
                        rendered(SOURCE_CONTROLS, affected_start, affected_end),
                        affected_start,
                        affected_end,
                    )
                    expected_child = source_scope_totals(
                        source_control_cursor,
                        rendered(CHILD_PACKAGE_AGE_CONTROLS, affected_start, affected_end),
                    )
                target_cursor.execute(
                    f'CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP'
                )
                copied_rows = 0
                for batch_start, batch_end in month_batches(affected_start, affected_end):
                    require_batch_space(directory)
                    transfer_path = directory / f'{batch_start:%Y%m}.copy'
                    try:
                        rows, byte_count, elapsed = copy_source_batch(source, batch_start, batch_end, transfer_path)
                        with target_cursor.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as copy, transfer_path.open('rb') as input_file:
                            while block := input_file.read(1_048_576):
                                copy.write(block)
                        if target_cursor.rowcount != rows:
                            raise RuntimeError(f'Target batch COPY differs: {target_cursor.rowcount} != {rows}')
                        copied_rows += rows
                        print(f'BATCH_PASS start={batch_start} end={batch_end} rows={rows} bytes={byte_count} elapsed_seconds={elapsed:.3f}', flush=True)
                    finally:
                        transfer_path.unlink(missing_ok=True)

                require_stage_integrity(target_cursor, affected_start, affected_end)
                if totals(target_cursor, STAGE, affected_start, affected_end) != expected:
                    raise RuntimeError('Staging daily totals differ from independent source control')
                if child_package_age_totals(target_cursor, STAGE, affected_start, affected_end) != expected_child:
                    raise RuntimeError('Staging BR-038 child-package control differs from source snapshot')
                target_cursor.execute(replace[0])
                target_cursor.execute(replace[1])
                if totals(target_cursor, TABLE, affected_start, affected_end) != expected:
                    raise RuntimeError('Persisted daily totals differ from independent source control')
                if child_package_age_totals(target_cursor, TABLE, affected_start, affected_end) != expected_child:
                    raise RuntimeError('Persisted BR-038 child-package control differs from source snapshot')
                if not has_br038_age_constraint(target_cursor):
                    raise RuntimeError('Existing BR-038 target constraint is absent')
                persisted_digest = fingerprints(target_cursor, target_fingerprint_sql(start, end))
                require_target_fingerprint_match(source_digest, persisted_digest, start, end, 'pre_commit')
                target.commit()
            source.rollback()
            print(f'TARGET_COMMIT changed_dates={len(dates)} replacement_window={affected_start}..{affected_end} copied_rows={copied_rows} elapsed_seconds={time.monotonic() - started:.3f}', flush=True)
        except Exception:
            target.rollback()
            source.rollback()
            raise
        finally:
            source.close()
            target.close()


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
    print(f'CONFIG object={TABLE} horizon={start}..{end} mode=target_fingerprint_diff', flush=True)
    if args.plan_only:
        print('SOURCE_PLAN ' + json.dumps(source_plan(start, end), sort_keys=True), flush=True)
    elif args.check_only:
        check_only(start, end)
    else:
        run_refresh(start, end)


if __name__ == '__main__':
    main()
