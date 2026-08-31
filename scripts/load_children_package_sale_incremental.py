#!/usr/bin/env python3
"""Synchronise children package sale without invoking full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_children_package_sale import COLUMNS,EXTRACT,STAGE,TABLE,TIMEOUT_SECONDS,br003_horizon,close_after_failure,combine_expected,config,month_batches,prepare_source_batch,rendered,require_reconciliation,require_stage_contract
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/children_package_sale_incremental.json';N=tuple(x.strip() for x in COLUMNS.split(','));COL=', '.join(N);SCOL=', '.join('stage.'+x for x in N);EQ=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in N)
def config_ok(path):
 x=json.loads(path.read_text());
 if x.get('objects')!=[TABLE] or x.get('mode')!='target_row_diff' or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected children package incremental configuration')
def delta(c):
 c.execute(f'SELECT count(*) FROM ((SELECT {COL} FROM {STAGE} EXCEPT ALL SELECT {COL} FROM {TABLE}) UNION ALL (SELECT {COL} FROM {TABLE} EXCEPT ALL SELECT {COL} FROM {STAGE})) d');return c.fetchone()[0]
def run(start,end):
 with tempfile.TemporaryDirectory(prefix='children_package_incremental_') as tmp:
  owner=connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source');target=None
  try:
   with owner.cursor() as o:
    o.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');o.execute(f"SET LOCAL statement_timeout='{TIMEOUT_SECONDS}s'");o.execute('SELECT pg_export_snapshot()');snapshot=o.fetchone()[0]
   target=connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart')
   with target.cursor() as c:
    c.execute('BEGIN');c.execute('SELECT to_regclass(%s)',(TABLE,))
    if c.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing target')
    c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TABLE+':incremental',));c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP');expected_total=None
    for batch_start,batch_end in month_batches(start,end):
     transfer,rows,_,_,expected=prepare_source_batch(snapshot,batch_start,batch_end,start,end,Path(tmp))
     try:
      with c.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as cp,transfer.open('rb') as inp:
       while block:=inp.read(1048576):cp.write(block)
      if c.rowcount!=rows:raise RuntimeError('Target batch COPY differs')
     finally:transfer.unlink(missing_ok=True)
     expected_total=combine_expected(expected_total,expected)
    require_stage_contract(c,start,end,expected_total);before=delta(c)
    if not before:target.commit();owner.rollback();print('NO_CHANGES');return
    c.execute(f'DELETE FROM {TABLE} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQ})');c.execute(f'INSERT INTO {TABLE} ({COL}) SELECT {SCOL} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TABLE} target WHERE {EQ})')
    if delta(c):raise RuntimeError('Pre-commit exact mismatch')
    require_reconciliation(c,expected_total,start,end,'pre_commit');target.commit();owner.rollback();print(f'TARGET_COMMIT delta_before={before}')
  except Exception:close_after_failure(owner);close_after_failure(target);raise
  finally:
   if target is not None:target.close()
def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();config_ok(a.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
