#!/usr/bin/env python3
"""Atomically rebuild mart.promo_application from the reviewed source extract.

Execution is forbidden until a separate physical-admission package is approved.
"""
from __future__ import annotations
import argparse, os, re, shutil, sys, tempfile
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
from scripts.load_children_package_sale import br003_horizon, config

EXTRACT = ROOT / 'sql/marts/promo_application_source_extract.sql'
DDL = ROOT / 'sql/marts/promo_application_ddl.sql'
RECON = ROOT / 'sql/tests/promo_application_reconciliation.sql'
TABLE = 'mart.promo_application'
COLUMNS = ('report_row_id,source_kind,application_date,client_key,club_name,membership_code,'
           'promo_name,serial_name,discount_name,discount_id,discount_method,service_name,'
           'business_direction,gift_name,gift_recipient_membership_code,client_stage,'
           'discount_amount,price_before_discount,bought_membership_45d_flag,'
           'bought_dpfu_45d_flag,friend_bought_membership_45d_flag')

def render(path: Path, start: date, end: date) -> str:
    return path.read_text(encoding='utf-8').strip().rstrip(';').replace(
        '$1::date', f"DATE '{start.isoformat()}'").replace('$2::date', f"DATE '{end.isoformat()}'")

def open_db(prefix: str, name: str):
    return connect_with_retry(lambda: psycopg.connect(**(config(prefix) | {
        'application_name': name, 'connect_timeout': 15, 'keepalives': 1,
        'keepalives_idle': 60, 'keepalives_interval': 15, 'keepalives_count': 4})),
        endpoint=prefix.lower().rstrip('_'))

def execute_ddl(cur) -> None:
    body = '\n'.join(x for x in DDL.read_text(encoding='utf-8').splitlines()
                     if not x.lstrip().startswith('--'))
    for statement in (x.strip() for x in body.split(';')):
        if statement: cur.execute(statement)

def rows_from_source(start: date, end: date, transfer: Path) -> None:
    source = open_db('SOURCE_', 'promo_application_source_copy')
    try:
        with source.cursor() as cur, transfer.open('wb') as out:
            cur.execute('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
            cur.execute("SET LOCAL statement_timeout = '120s'")
            with cur.copy('COPY (' + render(EXTRACT, start, end) +
                          ') TO STDOUT WITH (FORMAT BINARY)') as copied:
                for block in copied: out.write(block)
            cur.execute('ROLLBACK')
    finally:
        source.close()

def reconcile(cur, expected: tuple[object, ...], start: date, end: date) -> None:
    body = '\n'.join(x for x in RECON.read_text(encoding='utf-8').splitlines()
                     if not x.lstrip().startswith('--'))
    args = expected + (start, end)
    cur.execute(re.sub(r'\$(\d+)', '%s', body),
                tuple(args[int(x.group(1))-1] for x in re.finditer(r'\$(\d+)', body)))
    failed = [row[:3] for row in cur.fetchall() if row[4] != 'PASS']
    if failed: raise RuntimeError(f'reconciliation failed: {failed}')

def run(initial: bool) -> None:
    start, end = br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
    if shutil.disk_usage('/tmp').free < 2 * 1024**3:
        raise RuntimeError('less than 2 GiB free for source-first temporary COPY')
    with tempfile.TemporaryDirectory(prefix='promo_application_') as folder:
        transfer = Path(folder) / 'source.copy'
        rows_from_source(start, end, transfer)
        target = open_db('MART_', 'promo_application_atomic_delivery')
        try:
            with target.cursor() as cur:
                cur.execute('BEGIN')
                cur.execute("SELECT pg_advisory_xact_lock(hashtext('mart.promo_application'))")
                if initial: execute_ddl(cur)
                cur.execute('CREATE TEMP TABLE promo_application_stage (LIKE mart.promo_application INCLUDING ALL) ON COMMIT DROP')
                with transfer.open('rb') as inp, cur.copy(
                    f'COPY promo_application_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as copied:
                    while block := inp.read(1_048_576): copied.write(block)
                cur.execute('SELECT count(*), count(*) FILTER (WHERE source_kind=%s), count(*) FILTER (WHERE source_kind=%s), min(application_date), max(application_date), coalesce(sum(discount_amount),0), coalesce(sum(price_before_discount),0) FROM promo_application_stage', ('promo_gift','discount'))
                expected = cur.fetchone()
                cur.execute(sql.SQL('LOCK TABLE {} IN ACCESS EXCLUSIVE MODE').format(sql.Identifier('mart','promo_application')))
                cur.execute('TRUNCATE mart.promo_application')
                cur.execute(f'INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM promo_application_stage')
                reconcile(cur, expected, start, end)
                cur.execute('COMMIT')
        except Exception:
            target.rollback()
            raise
        finally:
            target.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--initial', action='store_true')
    run(parser.parse_args().initial)
