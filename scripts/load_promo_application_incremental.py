#!/usr/bin/env python3
"""Synchronise promo applications without invoking the full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_promo_application import COLUMNS,TABLE,br003_horizon,open_db,reconcile,rows_from_source
CONFIG=ROOT/'config/promo_application_incremental.json';STAGE='_promo_application_incremental_stage';NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 actual=json.loads(path.read_text(encoding='utf-8'));expected={'objects':[TABLE],'mode':'target_row_diff','timezone':'Europe/Moscow','change_detection':'source_snapshot_to_target_exact_row_multiset_diff','deletion_policy':'delete_target_rows_absent_or_different_in_source_snapshot','no_change_policy':'no_final_target_dml'}
 if any(actual.get(k)!=v for k,v in expected.items()) or actual.get('watermark') is not None or actual.get('incremental_sla') is not None:raise RuntimeError('Unexpected promo application incremental configuration')
def delta(cursor):
 cursor.execute(f'SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TABLE}) UNION ALL (SELECT {SELECTED} FROM {TABLE} EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d');return cursor.fetchone()[0]
def run(start,end):
 started=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='promo_application_incremental_') as folder:
  transfer=Path(folder)/'source.copy';expected=rows_from_source(start,end,transfer);target=open_db('MART_','promo_application_incremental')
  try:
   with target.cursor() as cursor:
    cursor.execute('BEGIN');cursor.execute('SELECT to_regclass(%s)',(TABLE,))
    if cursor.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing target')
    cursor.execute("SELECT pg_advisory_xact_lock(hashtext('mart.promo_application:incremental'))");cursor.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP')
    with transfer.open('rb') as source,cursor.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as cp:
     while block:=source.read(1048576):cp.write(block)
    before=delta(cursor)
    if not before:target.commit();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
    cursor.execute(f'DELETE FROM {TABLE} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})')
    cursor.execute(f'INSERT INTO {TABLE} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TABLE} target WHERE {EQUALITY})')
    if delta(cursor):raise RuntimeError('Pre-commit exact mismatch')
    reconcile(cursor,expected,start,end);target.commit();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
  except Exception:target.rollback();raise
  finally:target.close()
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',type=Path,default=CONFIG);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--plan-only',action='store_true');mode.add_argument('--run',action='store_true',help='perform approved target DML');args=parser.parse_args();load_config(args.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if args.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
