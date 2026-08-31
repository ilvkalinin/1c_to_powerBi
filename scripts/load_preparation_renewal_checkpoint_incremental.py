#!/usr/bin/env python3
"""Synchronise preparation renewal checkpoints without invoking full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_preparation_renewal_checkpoint import COLUMNS,TARGET,br003_horizon,config,copy_source_batch,extract_query,quarter_windows,render,require_reconciliation,source_controls
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/preparation_renewal_checkpoint_incremental.json';STAGE='_preparation_renewal_checkpoint_incremental_stage';NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 actual=json.loads(path.read_text(encoding='utf-8'));expected={'objects':[TARGET],'mode':'target_row_diff','timezone':'Europe/Moscow','change_detection':'source_snapshot_to_target_exact_row_multiset_diff','deletion_policy':'delete_target_rows_absent_or_different_in_source_snapshot','no_change_policy':'no_final_target_dml'}
 if any(actual.get(k)!=v for k,v in expected.items()) or actual.get('watermark') is not None or actual.get('incremental_sla') is not None:raise RuntimeError('Unexpected preparation checkpoint incremental configuration')
def delta(cursor):
 cursor.execute(f'SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET}) UNION ALL (SELECT {SELECTED} FROM {TARGET} EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d');return cursor.fetchone()[0]
def run(start,end):
 started=time.monotonic();query=extract_query()
 with tempfile.TemporaryDirectory(prefix='preparation_checkpoint_incremental_') as directory:
  with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
   try:
    with source.cursor() as source_cursor,target.cursor() as cursor:
     source_cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');cursor.execute('BEGIN');cursor.execute('SELECT to_regclass(%s)',(TARGET,))
     if cursor.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing target')
     cursor.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));cursor.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP');totals=[0,0,0,0]
     for batch_start,batch_end in quarter_windows(start,end):
      expected=source_controls(source_cursor,batch_start,batch_end);path=Path(directory)/f'{batch_start.isoformat()}.copy';copied=copy_source_batch(source_cursor,render(query,batch_start,batch_end),path)
      if copied!=expected[0]:raise RuntimeError(f'Source batch differs from COPY: {copied} != {expected[0]}')
      with path.open('rb') as src,cursor.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as cp:
       while block:=src.read(1048576):cp.write(block)
      path.unlink()
      for i in range(4):totals[i]+=expected[i]
     before=delta(cursor)
     if not before:target.commit();source.rollback();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
     cursor.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})')
     cursor.execute(f'INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE {EQUALITY})')
     if delta(cursor):raise RuntimeError('Pre-commit exact mismatch')
     require_reconciliation(cursor,tuple(totals),start,end);target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
   except Exception:target.rollback();source.rollback();raise
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',type=Path,default=CONFIG);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--plan-only',action='store_true');mode.add_argument('--run',action='store_true',help='perform approved target DML');args=parser.parse_args();load_config(args.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if args.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
