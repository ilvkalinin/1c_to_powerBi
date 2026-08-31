#!/usr/bin/env python3
"""Refresh source-different mart.contract_usage contract keys only."""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_contract_usage import COLUMNS, EXTRACT, TABLE, br003_horizon, render, source_connection, target_connection

DEFAULT_CONFIG = ROOT / 'config/contract_usage_incremental.json'
SOURCE_FINGERPRINT = ROOT / 'sql/marts/contract_usage_incremental_source_fingerprint.sql'
TARGET_FINGERPRINT = ROOT / 'sql/marts/contract_usage_incremental_target_fingerprint.sql'
TARGET_REPLACE = ROOT / 'sql/marts/contract_usage_incremental_target_replace.sql'
MARKER = '/*__CONTRACT_USAGE_FACT__*/'
STAGE = '_contract_usage_incremental_stage'


def load_config(path: Path) -> None:
    payload = json.loads(path.read_text(encoding='utf-8'))
    expected = {'object': TABLE, 'mode': 'target_fingerprint_diff', 'timezone': 'Europe/Moscow',
                'change_detection': 'source_target_double_md5_by_contract_id',
                'deletion_policy': 'delete_source_absent_contract_keys', 'no_change_policy': 'no_target_dml'}
    if any(payload.get(key) != value for key, value in expected.items()):
        raise RuntimeError('Unexpected incremental config')
    if payload.get('watermark') is not None or payload.get('incremental_sla') is not None:
        raise RuntimeError('Unvalidated watermark or incremental SLA is forbidden')


def source_fact(start, end) -> str:
    return render(EXTRACT, (start, end))


def source_fingerprint(start, end) -> str:
    template = SOURCE_FINGERPRINT.read_text(encoding='utf-8')
    if template.count(MARKER) != 1:
        raise RuntimeError('Unexpected source fingerprint marker')
    return template.replace(MARKER, source_fact(start, end))


def fingerprints(cursor, query: str) -> dict[str, tuple[str, str]]:
    cursor.execute(query)
    result = {key: (first, second) for key, first, second in cursor}
    if any(not re.fullmatch(r'[0-9a-f]{32}', key) or not first or not second for key, (first, second) in result.items()):
        raise RuntimeError('Unexpected contract fingerprint key/digest')
    return result


def changes(source: dict[str, tuple[str, str]], target: dict[str, tuple[str, str]]) -> list[str]:
    return sorted(key for key in set(source) | set(target) if source.get(key) != target.get(key))


def selected_source_fact(start, end, keys: list[str]) -> str:
    if not keys:
        return source_fact(start, end) + ' WHERE false'
    if len(keys) == 1:
        predicate = f"contract_id = '{keys[0]}'"
    else:
        predicate = 'contract_id IN (' + ','.join(f"'{key}'" for key in keys) + ')'
    return 'WITH fact AS (' + source_fact(start, end) + ') SELECT * FROM fact WHERE ' + predicate


def copy_source(cursor, query: str, path: Path) -> int:
    with path.open('wb') as output, cursor.copy(f'COPY ({query}) TO STDOUT WITH (FORMAT BINARY)') as copied:
        for block in copied:
            output.write(block)
    return cursor.rowcount


def stage_contract(cursor) -> None:
    cursor.execute(f'''SELECT count(*) FROM (SELECT 1 FROM {STAGE} GROUP BY contract_id HAVING count(*) > 1) AS duplicates''')
    if cursor.fetchone()[0]:
        raise RuntimeError('Incremental stage has duplicate contract keys')
    cursor.execute(f'''SELECT count(*) FROM {STAGE} WHERE contract_id IS NULL OR contract_code IS NULL OR membership_start_date IS NULL OR membership_end_date IS NULL OR membership_end_date <= membership_start_date OR active_calendar_months <= 0 OR visit_count <= 0''')
    if cursor.fetchone()[0]:
        raise RuntimeError('Incremental stage violates contract usage rules')


def run_refresh(start, end) -> None:
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='contract_usage_incremental_') as folder:
        transfer = Path(folder) / 'contracts.copy'
        source = source_connection('contract_usage_incremental_source')
        target = target_connection('contract_usage_incremental_target')
        try:
            with source.cursor() as source_cursor, target.cursor() as target_cursor:
                source_cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
                source_cursor.execute("SET LOCAL statement_timeout = '300s'")
                source_state = fingerprints(source_cursor, source_fingerprint(start, end))
                target_cursor.execute('BEGIN')
                target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (f'{TABLE}:incremental',))
                target_cursor.execute('SELECT to_regclass(%s)', (TABLE,))
                if target_cursor.fetchone()[0] is None:
                    raise RuntimeError('Incremental refresh requires the existing target')
                target_state = fingerprints(target_cursor, TARGET_FINGERPRINT.read_text(encoding='utf-8'))
                keys = changes(source_state, target_state)
                print(f'SOURCE_FINGERPRINT source_contracts={len(source_state)} changed_contracts={len(keys)}', flush=True)
                if not keys:
                    target.commit(); source.rollback(); print(f'NO_CHANGES elapsed_seconds={time.monotonic() - started:.3f}', flush=True); return
                source_rows = copy_source(source_cursor, selected_source_fact(start, end, keys), transfer)
                target_cursor.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING ALL) ON COMMIT DROP')
                if source_rows:
                    with target_cursor.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as copied, transfer.open('rb') as input_file:
                        while block := input_file.read(1_048_576): copied.write(block)
                    if target_cursor.rowcount != source_rows: raise RuntimeError('Target COPY count differs from source')
                stage_contract(target_cursor)
                replacement = [item.strip() for item in TARGET_REPLACE.read_text(encoding='utf-8').split(';') if item.strip()]
                if len(replacement) != 2: raise RuntimeError('Unexpected target replacement statements')
                target_cursor.execute(replacement[0], (keys,)); target_cursor.execute(replacement[1])
                persisted = fingerprints(target_cursor, TARGET_FINGERPRINT.read_text(encoding='utf-8'))
                if changes(source_state, persisted): raise RuntimeError('Pre-commit source/target fingerprint mismatch')
                target.commit(); source.rollback()
                print(f'TARGET_COMMIT changed_contracts={len(keys)} staged_rows={source_rows} elapsed_seconds={time.monotonic() - started:.3f}', flush=True)
        except Exception:
            target.rollback(); source.rollback(); raise
        finally:
            source.close(); target.close(); transfer.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check-only', action='store_true')
    mode.add_argument('--run', action='store_true')
    args = parser.parse_args(); load_config(args.config)
    start, end = br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
    print(f'CONFIG object={TABLE} horizon={start}..{end} mode=target_fingerprint_diff', flush=True)
    if args.check_only:
        source = source_connection('contract_usage_incremental_check_source'); target = target_connection('contract_usage_incremental_check_target')
        try:
            with source.cursor() as sc, target.cursor() as tc:
                sc.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY'); tc.execute('BEGIN READ ONLY')
                difference = changes(fingerprints(sc, source_fingerprint(start, end)), fingerprints(tc, TARGET_FINGERPRINT.read_text(encoding='utf-8')))
            source.rollback(); target.rollback(); print(f'CHECK_ONLY changed_contracts={len(difference)}', flush=True)
        finally:
            source.close(); target.close()
    else:
        run_refresh(start, end)


if __name__ == '__main__':
    main()
