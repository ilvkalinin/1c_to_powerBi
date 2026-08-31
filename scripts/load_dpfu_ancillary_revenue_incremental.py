#!/usr/bin/env python3
"""Synchronise DPFU ancillary revenue scope without full rebuild."""
from __future__ import annotations
import argparse,json,sys,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_dpfu_ancillary_revenue import COLUMNS,EXTRACTS,SOURCE_COLUMNS,bound_sql,br003_horizon,config,control_queries,controls,require_stage_integrity
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/dpfu_ancillary_revenue_incremental.json';TARGET='mart.ancillary_revenue_movement';STAGE='_dpfu_ancillary_revenue_incremental_stage';NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 x=json.loads(path.read_text(encoding='utf-8'))
 if x.get('objects')!=[TARGET] or x.get('scope')!='dpfu' or x.get('mode')!='scoped_target_row_diff' or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected DPFU ancillary incremental configuration')
def delta(c):
 c.execute(f"SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET} WHERE revenue_scope='dpfu') UNION ALL (SELECT {SELECTED} FROM {TARGET} WHERE revenue_scope='dpfu' EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d");return c.fetchone()[0]
def reception_controls(c):
 c.execute("SELECT count(*)::bigint,coalesce(sum(revenue_amount),0)::numeric FROM mart.ancillary_revenue_movement WHERE revenue_scope='reception'");return c.fetchone()
def run(start,end):
 started=time.monotonic()
 with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
  try:
   with source.cursor() as s,target.cursor() as c:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');expected={}
    for query in control_queries():
     s.execute(query,(start,end));kind,rows,quantity,revenue=s.fetchone();expected[kind]=(rows,quantity,revenue)
    if set(expected)!={'7575','7646'} or any(v[0]==0 for v in expected.values()):raise RuntimeError('Unexpected independent source controls')
    c.execute('BEGIN');c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':dpfu-incremental',));reception_before=reception_controls(c);c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
    for path in EXTRACTS:
     extract=bound_sql(path,start,end).rstrip().removesuffix(';');projection=f"SELECT {SOURCE_COLUMNS}, 'dpfu'::text AS revenue_scope FROM ({extract}) source_extract"
     with c.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc,s.copy(f'COPY ({projection}) TO STDOUT WITH (FORMAT BINARY)') as sc:
      for block in sc:tc.write(block)
    if controls(c,STAGE)!=expected:raise RuntimeError('Staging controls differ from source snapshot')
    require_stage_integrity(c);before=delta(c)
    if not before:target.commit();source.rollback();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
    c.execute(f"DELETE FROM {TARGET} target WHERE target.revenue_scope='dpfu' AND NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})")
    c.execute(f"INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE target.revenue_scope='dpfu' AND {EQUALITY})")
    if delta(c):raise RuntimeError('Pre-commit exact mismatch')
    if controls(c,"mart.ancillary_revenue_movement WHERE revenue_scope = 'dpfu'")!=expected:raise RuntimeError('Persisted DPFU controls differ from source')
    if reception_controls(c)!=reception_before:raise RuntimeError('Reception scope changed during DPFU sync')
    target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
  except Exception:target.rollback();source.rollback();raise
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();load_config(a.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=scoped_target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
