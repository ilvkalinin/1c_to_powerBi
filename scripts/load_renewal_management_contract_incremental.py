#!/usr/bin/env python3
"""Synchronise current renewal contracts without invoking the full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile,time
from datetime import date
from pathlib import Path
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_renewal_management_contract import COLUMNS,EXTRACT,TARGET,config,copy_source,current_m_horizon,render,require_reconciliation,source_controls
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/renewal_management_incremental.json';STAGE='_renewal_management_contract_incremental_stage';NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 x=json.loads(path.read_text(encoding='utf-8'))
 if x.get('mode')!='current_state_row_diff_then_append_observation' or x.get('objects')!=[TARGET,'mart.renewal_management_contract_observation'] or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected renewal incremental configuration')
def delta(c):
 c.execute(f'SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET}) UNION ALL (SELECT {SELECTED} FROM {TARGET} EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d');return c.fetchone()[0]
def run(today:date):
 start,end=current_m_horizon(today);started=time.monotonic();query=render(EXTRACT.read_text(encoding='utf-8').strip().rstrip(';'),start,end)
 with tempfile.TemporaryDirectory(prefix='renewal_management_incremental_') as d:
  path=Path(d)/'source.copy'
  with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source:
   with source.cursor() as s:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');expected=source_controls(s,start,end);rows=copy_source(s,query,path)
    if rows!=expected[0]:raise RuntimeError(f'Source rows differ from COPY: {rows} != {expected[0]}');source.rollback()
  with connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
   try:
    with target.cursor() as c:
     c.execute('BEGIN');c.execute('SELECT to_regclass(%s)',(TARGET,))
     if c.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing target')
     c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
     with path.open('rb') as inp,c.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as cp:
      while block:=inp.read(1048576):cp.write(block)
     before=delta(c)
     if not before:target.commit();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
     c.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})');c.execute(f'INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE {EQUALITY})')
     if delta(c):raise RuntimeError('Pre-commit exact mismatch')
     require_reconciliation(c,expected);target.commit();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
   except Exception:target.rollback();raise
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',type=Path,default=CONFIG);p.add_argument('--today',type=date.fromisoformat,default=date.today());m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();load_config(a.config)
 if a.plan_only:print(f'PLAN_OK mode=current_state_row_diff horizon={current_m_horizon(a.today)[0]}..{current_m_horizon(a.today)[1]}');return
 run(a.today)
if __name__=='__main__':main()
