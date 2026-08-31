#!/usr/bin/env python3
"""Atomically refresh the confirmed two-month late-change window for two client-base facts.

This separate runner reuses reviewed source extracts and validation helpers but
never calls the full-rebuild runner's run_once(). It has no DDL path.
"""

from __future__ import annotations

import argparse
import json
import subprocess
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

from scripts.load_client_base_snapshot_retention import (
    RETENTION_COLUMNS,
    RETENTION_CONTROLS,
    RETENTION_EXTRACT,
    SNAPSHOT_COLUMNS,
    SNAPSHOT_CONTROLS,
    SNAPSHOT_EXTRACT,
    TransportRestartRequired,
    close_after_failure,
    config,
    connect_source_with_retry,
    copy_prepared_batch,
    copy_source_batch,
    deserialize_expected,
    mart_config,
    month_batches,
    rendered,
    require_batch_space,
    require_retention_stage,
    require_snapshot_stage,
    require_target_state,
    retention_expected,
    retention_totals,
    snapshot_expected,
    snapshot_totals,
    source_reader,
    statements,
)
from scripts.mart_connection import connect_with_retry


DEFAULT_CONFIG = ROOT / 'config/client_base_snapshot_retention_incremental.json'
SNAPSHOT_REPLACE = ROOT / 'sql/marts/client_base_snapshot_incremental_target_replace.sql'
RETENTION_REPLACE = ROOT / 'sql/marts/client_base_retention_incremental_target_replace.sql'
SOURCE_BATCH_MAX_ATTEMPTS = 3
SOURCE_BATCH_TIMEOUT_SECONDS = 180


def month_start(day: date) -> date:
    return date(day.year, day.month, 1)


def subtract_months(day: date, months: int) -> date:
    absolute = day.year * 12 + day.month - 1 - months
    return date(absolute // 12, absolute % 12 + 1, 1)


def load_config(path: Path) -> int:
    payload = json.loads(path.read_text(encoding='utf-8'))
    if payload.get('objects') != ['mart.client_base_snapshot', 'mart.client_base_retention']:
        raise RuntimeError('Incremental config targets unexpected facts')
    if payload.get('mode') != 'two_month_sliding_window' or payload.get('timezone') != 'Europe/Moscow':
        raise RuntimeError('Incremental config has an unexpected mode/timezone')
    months = int(payload.get('late_change_months', 0))
    if months != 2:
        raise RuntimeError('Only the confirmed two-month late-change window is allowed')
    if payload.get('watermark') is not None or payload.get('incremental_sla') is not None:
        raise RuntimeError('Unvalidated watermark or incremental SLA is forbidden')
    return months


def bounds(today: date, months: int) -> tuple[date, date]:
    return subtract_months(month_start(today), months - 1), date.fromordinal(today.toordinal() + 1)


def serialize_expected(fact: str, expected: dict) -> list[dict[str, object]]:
    if fact == 'snapshot':
        return [{'key': [day.isoformat(), scope], 'value': value} for (day, scope), value in expected.items()]
    return [
        {'key': [day.isoformat(), kind, comparison.isoformat(), scope], 'value': list(value)}
        for (day, kind, comparison, scope), value in expected.items()
    ]


def source_batch(args: argparse.Namespace) -> None:
    start, end = date.fromisoformat(args.start), date.fromisoformat(args.end)
    fact = args.fact
    extract = SNAPSHOT_EXTRACT if fact == 'snapshot' else RETENTION_EXTRACT
    controls = SNAPSHOT_CONTROLS if fact == 'snapshot' else RETENTION_CONTROLS
    transfer, metadata = Path(args.transfer), Path(args.metadata)
    with source_reader(args.snapshot_id) as source:
        with source.cursor() as cursor:
            if fact == 'retention':
                cursor.execute("SET LOCAL work_mem = '128MB'")
                expected = retention_expected(cursor, rendered(controls, start, end))
            else:
                expected = snapshot_expected(cursor, rendered(controls, start, end), start, end)
        require_batch_space(transfer.parent)
        rows, byte_count, elapsed = copy_source_batch(source, extract, start, end, transfer)
        metadata.write_text(json.dumps({
            'rows': rows, 'bytes': byte_count, 'elapsed': elapsed,
            'expected': serialize_expected(fact, expected),
        }), encoding='utf-8')
        source.rollback()


def prepare_source_batch(fact: str, snapshot_id: str, start: date, end: date, directory: Path):
    transfer = directory / f'{fact}_{start:%Y%m}.copy'
    metadata = directory / f'{fact}_{start:%Y%m}.json'
    command = [
        sys.executable, str(Path(__file__).resolve()), '--source-batch', '--fact', fact,
        '--start', start.isoformat(), '--end', end.isoformat(), '--snapshot-id', snapshot_id,
        '--transfer', str(transfer), '--metadata', str(metadata),
    ]
    for attempt in range(1, SOURCE_BATCH_MAX_ATTEMPTS + 1):
        transfer.unlink(missing_ok=True)
        metadata.unlink(missing_ok=True)
        try:
            completed = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=SOURCE_BATCH_TIMEOUT_SECONDS,
                check=False,
            )
        except subprocess.TimeoutExpired:
            print(
                f'SOURCE_WORKER_TIMEOUT fact={fact} start={start} attempt={attempt} '
                f'seconds={SOURCE_BATCH_TIMEOUT_SECONDS}',
                flush=True,
            )
            continue
        if completed.returncode == 0 and transfer.exists() and metadata.exists():
            payload = json.loads(metadata.read_text(encoding='utf-8'))
            return transfer, payload['rows'], int(payload['bytes']), float(payload['elapsed']), deserialize_expected(fact, payload['expected'])
        diagnostic = (completed.stderr or completed.stdout).strip().splitlines()
        reason = diagnostic[-1] if diagnostic else 'no_worker_diagnostic'
        print(f'SOURCE_WORKER_RETRY fact={fact} start={start} attempt={attempt} reason={reason[:300]}', flush=True)
    raise TransportRestartRequired(f'Source worker exhausted retries fact={fact} start={start}')


def run_refresh(start: date, end: date) -> None:
    snapshot_replace = statements(SNAPSHOT_REPLACE, start, end)
    retention_replace = statements(RETENTION_REPLACE, start, end)
    if len(snapshot_replace) != 2 or len(retention_replace) != 2:
        raise RuntimeError('Unexpected incremental replacement statement count')
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='client_base_snapshot_retention_incremental_') as raw_directory:
        directory = Path(raw_directory)
        owner = connect_source_with_retry('client_base_snapshot_retention_incremental_owner')
        prepared: list[tuple[str, Path, int | None, int, float, date, date, dict]] = []
        try:
            with owner.cursor() as cursor:
                cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
                cursor.execute('SELECT pg_export_snapshot()')
                snapshot_id = cursor.fetchone()[0]
            for batch_start, batch_end in month_batches(start, end):
                for fact in ('snapshot', 'retention'):
                    transfer, rows, byte_count, elapsed, expected = prepare_source_batch(
                        fact, snapshot_id, batch_start, batch_end, directory
                    )
                    prepared.append((fact, transfer, rows, byte_count, elapsed, batch_start, batch_end, expected))
                    print(f'SOURCE_STAGE_PASS fact={fact} start={batch_start} end={batch_end} controls={len(expected)} rows={rows} bytes={byte_count} elapsed_seconds={elapsed:.3f}', flush=True)
            owner.rollback()
        finally:
            owner.close()

        target = connect_with_retry(lambda: psycopg.connect(**mart_config('client_base_snapshot_retention_incremental_target')), endpoint='mart')
        try:
            with target.cursor() as cursor:
                cursor.execute('BEGIN')
                cursor.execute("SET LOCAL lock_timeout = '60s'")
                cursor.execute("SET LOCAL idle_in_transaction_session_timeout = '240s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ('mart.client_base_snapshot_retention:incremental',))
                require_target_state(cursor, initial=False)
                cursor.execute('CREATE TEMP TABLE _client_base_snapshot_incremental_stage (LIKE mart.client_base_snapshot INCLUDING DEFAULTS) ON COMMIT DROP')
                cursor.execute('CREATE TEMP TABLE _client_base_retention_incremental_stage (LIKE mart.client_base_retention INCLUDING DEFAULTS) ON COMMIT DROP')
                snapshot_expected_values, retention_expected_values = {}, {}
                snapshot_rows = retention_rows = 0
                for fact, transfer, rows, byte_count, elapsed, batch_start, batch_end, expected in prepared:
                    if fact == 'snapshot':
                        stage, columns, collected = '_client_base_snapshot_incremental_stage', SNAPSHOT_COLUMNS, snapshot_expected_values
                    else:
                        stage, columns, collected = '_client_base_retention_incremental_stage', RETENTION_COLUMNS, retention_expected_values
                    if collected.keys() & expected.keys():
                        raise RuntimeError(f'{fact} controls overlap across monthly batches')
                    collected.update(expected)
                    copied = copy_prepared_batch(cursor, target, stage, columns, transfer, rows, byte_count, elapsed, batch_start, batch_end, expected)
                    if fact == 'snapshot': snapshot_rows += copied
                    else: retention_rows += copied
                require_snapshot_stage(cursor, start, end)
                require_retention_stage(cursor, start, end)
                if snapshot_totals(cursor, '_client_base_snapshot_incremental_stage') != snapshot_expected_values:
                    raise RuntimeError('Snapshot stage differs from independent source controls')
                if retention_totals(cursor, '_client_base_retention_incremental_stage') != retention_expected_values:
                    raise RuntimeError('Retention stage differs from independent source controls')
                for statement in snapshot_replace + retention_replace:
                    cursor.execute(statement)
                if snapshot_totals(cursor, 'mart.client_base_snapshot') != snapshot_expected_values:
                    raise RuntimeError('Snapshot target differs from source controls')
                if retention_totals(cursor, 'mart.client_base_retention') != retention_expected_values:
                    raise RuntimeError('Retention target differs from source controls')
                target.commit()
            print(f'TARGET_COMMIT window={start}..{end} snapshot_rows={snapshot_rows} retention_rows={retention_rows} elapsed_seconds={time.monotonic() - started:.3f}', flush=True)
        except Exception:
            close_after_failure('target', target)
            raise
        finally:
            if not target.closed:
                target.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--plan-only', action='store_true')
    mode.add_argument('--run', action='store_true')
    parser.add_argument('--source-batch', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--fact', choices=('snapshot', 'retention'), help=argparse.SUPPRESS)
    parser.add_argument('--start', help=argparse.SUPPRESS)
    parser.add_argument('--end', help=argparse.SUPPRESS)
    parser.add_argument('--snapshot-id', help=argparse.SUPPRESS)
    parser.add_argument('--transfer', help=argparse.SUPPRESS)
    parser.add_argument('--metadata', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.source_batch:
        required = ('fact', 'start', 'end', 'snapshot_id', 'transfer', 'metadata')
        if any(getattr(args, item) is None for item in required):
            parser.error('Incomplete --source-batch arguments')
        source_batch(args)
        return
    if not args.plan_only and not args.run:
        parser.error('one of --plan-only or --run is required')
    months = load_config(args.config)
    start, end = bounds(datetime.now(ZoneInfo('Europe/Moscow')).date(), months)
    print(f'CONFIG window={start}..{end} months={months} mode=two_month_sliding_window', flush=True)
    if args.plan_only:
        print('PLAN_ONLY no DML; use existing measured per-month source baselines', flush=True)
    else:
        run_refresh(start, end)


if __name__ == '__main__':
    main()
