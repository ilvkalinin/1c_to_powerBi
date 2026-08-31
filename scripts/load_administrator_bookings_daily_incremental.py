#!/usr/bin/env python3
"""Synchronise administrator bookings without invoking full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_administrator_bookings_daily import COLUMNS,TARGET,br003_horizon,config,copy_source_month,month_windows,relation_exists,require_reconciliation,source_controls
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/administrator_bookings_daily_incremental.json';STAGE='_administrator_bookings_daily_incremental_stage';N=tuple(x.strip() for x in COLUMNS.split(','));COL=', '.join(N);SCOL=', '.join('stage.'+x for x in N);EQ=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in N)
def config_ok(path):
 x=json.loads(path.read_text());
 if x.get('objects')!=[TARGET] or x.get('mode')!='target_row_diff' or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected administrator bookings incremental configuration')
def delta(c):
 c.execute(f'SELECT count(*) FROM ((SELECT {COL} FROM {STAGE} EXCEPT ALL SELECT {COL} FROM {TARGET}) UNION ALL (SELECT {COL} FROM {TARGET} EXCEPT ALL SELECT {COL} FROM {STAGE})) d');return c.fetchone()[0]
def run(start,end):
 with tempfile.TemporaryDirectory(prefix='administrator_bookings_incremental_') as d:
  with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
   try:
    with source.cursor(row_factory=psycopg.rows.dict_row) as s,target.cursor() as c:
     s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');expected=source_controls(s,start,end)
     c.execute('BEGIN');
     if not relation_exists(c):raise RuntimeError('Incremental refresh requires existing target')
     c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP');query_template=(ROOT/'sql/marts/administrator_bookings_daily_extract.sql').read_text().strip().rstrip(';');copied=0
     for batch_start,batch_end in month_windows(start,end):
      query=query_template.replace('$1::date',f"DATE '{batch_start.isoformat()}'").replace('$2::date',f"DATE '{batch_end.isoformat()}'");path=Path(d)/f'{batch_start.isoformat()}.copy';rows=copy_source_month(s,query,path)
      with c.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as cp,path.open('rb') as inp:
       while b:=inp.read(1048576):cp.write(b)
      copied+=rows
     if copied!=sum(int(row['expected_rows']) for row in expected):raise RuntimeError('Source copy differs from controls')
     before=delta(c)
     if not before:target.commit();source.rollback();print('NO_CHANGES');return
     c.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQ})');c.execute(f'INSERT INTO {TARGET} ({COL}) SELECT {SCOL} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE {EQ})')
     if delta(c):raise RuntimeError('Pre-commit exact mismatch')
     require_reconciliation(c,expected,start,end,copied);target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before}')
   except Exception:target.rollback();source.rollback();raise
def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();config_ok(a.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
