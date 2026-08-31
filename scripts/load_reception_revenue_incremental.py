#!/usr/bin/env python3
"""Synchronise reception revenue scope without full rebuild."""
from __future__ import annotations
import argparse,json,sys,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_reception_revenue import CATEGORIES,COLUMNS,EXTRACTS,bound_sql,br003_horizon,config,dpfu_controls,require_stage_integrity,scoped_controls,source_control_sql
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/reception_revenue_incremental.json';TARGET='mart.ancillary_revenue_movement';STAGE='_reception_revenue_incremental_stage';NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 x=json.loads(path.read_text());
 if x.get('objects')!=[TARGET] or x.get('scope')!='reception' or x.get('mode')!='scoped_target_row_diff' or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected reception incremental configuration')
def delta(c):
 c.execute(f"SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET} WHERE revenue_scope='reception') UNION ALL (SELECT {SELECTED} FROM {TARGET} WHERE revenue_scope='reception' EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d");return c.fetchone()[0]
def run(start,end):
 started=time.monotonic()
 with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
  try:
   with source.cursor() as s,target.cursor() as c:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');s.execute(source_control_sql(start,end));expected={(k,cat):(rows,q,r) for k,cat,rows,q,r in s}
    if not expected or {cat for _,cat in expected}!=CATEGORIES:raise RuntimeError('Source controls do not cover all categories')
    c.execute('BEGIN');c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':reception-incremental',));dpfu_before=dpfu_controls(c);c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
    for path in EXTRACTS:
     extract=bound_sql(path,start,end).rstrip().removesuffix(';')
     with c.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc,s.copy(f'COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)') as sc:
      for block in sc:tc.write(block)
    if scoped_controls(c,STAGE)!=expected:raise RuntimeError('Staging controls differ from source')
    require_stage_integrity(c);before=delta(c)
    if not before:target.commit();source.rollback();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
    c.execute(f"DELETE FROM {TARGET} target WHERE target.revenue_scope='reception' AND NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})");c.execute(f"INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE target.revenue_scope='reception' AND {EQUALITY})")
    if delta(c):raise RuntimeError('Pre-commit exact mismatch')
    if scoped_controls(c,"mart.ancillary_revenue_movement WHERE revenue_scope = 'reception'")!=expected:raise RuntimeError('Persisted reception controls differ')
    if dpfu_controls(c)!=dpfu_before:raise RuntimeError('DPFU scope changed during reception sync')
    target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
  except Exception:target.rollback();source.rollback();raise
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();load_config(a.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=scoped_target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
