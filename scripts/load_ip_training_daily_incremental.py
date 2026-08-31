#!/usr/bin/env python3
"""Synchronise IP training rows without calling the full rebuild loader."""
from __future__ import annotations
import argparse,json,sys,tempfile,time
from datetime import date,datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.load_ip_training_daily import COLUMNS,br003_horizon,config,extract_sql,require_client_key_quality,require_stage_integrity,source_controls,target_controls,bound_sql
from scripts.mart_connection import connect_with_retry
T='mart.ip_training_daily';S='_ip_training_daily_incremental_stage';COL=tuple(x.strip() for x in COLUMNS.split(','));CFG=ROOT/'config/ip_training_daily_incremental.json'
def check(p):
 x=json.loads(p.read_text());e={'object':T,'mode':'target_row_diff','timezone':'Europe/Moscow','change_detection':'source_snapshot_to_target_exact_row_diff','deletion_policy':'delete_target_rows_absent_or_different_in_source_snapshot','no_change_policy':'no_final_target_dml'}
 if any(x.get(k)!=v for k,v in e.items()) or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected incremental config')
def eq(a,b):return ' AND '.join(f'{a}.{x} IS NOT DISTINCT FROM {b}.{x}' for x in COL)
def delta(c):
 x=', '.join(COL);c.execute(f'SELECT count(*) FROM ((SELECT {x} FROM {S} EXCEPT ALL SELECT {x} FROM {T}) UNION ALL (SELECT {x} FROM {T} EXCEPT ALL SELECT {x} FROM {S})) d');return c.fetchone()[0]
def run(a,b):
 q=extract_sql(a,b);beg=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='ip_training_incremental_') as d:
  f=Path(d)/'source.copy'
  with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as src:
   with src.cursor() as c:
    c.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');require_client_key_quality(c,bound_sql(ROOT/'sql/marts/ip_training_daily_client_key_control.sql',a,b));expected=source_controls(c,q)
    with f.open('wb') as o,c.copy(f'COPY ({q}) TO STDOUT WITH (FORMAT BINARY)') as cp:
     for z in cp:o.write(z)
    rows=c.rowcount
   src.rollback()
  with connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as tar:
   try:
    with tar.cursor() as c:
     c.execute('BEGIN');c.execute("SET LOCAL statement_timeout='300s'");c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(T+':incremental',));c.execute('SELECT to_regclass(%s)',(T,))
     if c.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing target')
     c.execute(f'CREATE TEMP TABLE {S} (LIKE {T} INCLUDING DEFAULTS) ON COMMIT DROP')
     with f.open('rb') as i,c.copy(f"COPY {S} ({', '.join(COL)}) FROM STDIN (FORMAT BINARY)") as cp:
      while z:=i.read(1048576):cp.write(z)
     if c.rowcount!=rows:raise RuntimeError('Stage copy mismatch')
     c.execute(f'ALTER TABLE {S} RENAME TO _ip_training_daily_stage');require_stage_integrity(c)
     if target_controls(c,'_ip_training_daily_stage')!=(expected[1],expected[2]):raise RuntimeError('Stage controls differ')
     c.execute('ALTER TABLE _ip_training_daily_stage RENAME TO '+S);before=delta(c)
     if not before:tar.commit();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-beg:.3f}');return
     c.execute(f'DELETE FROM {T} target WHERE NOT EXISTS (SELECT 1 FROM {S} stage WHERE {eq("target","stage")})');deleted=c.rowcount
     c.execute(f"INSERT INTO {T} ({', '.join(COL)}) SELECT {', '.join('stage.'+x for x in COL)} FROM {S} stage WHERE NOT EXISTS (SELECT 1 FROM {T} target WHERE {eq('target','stage')})");inserted=c.rowcount
     if delta(c):raise RuntimeError('Pre-commit exact mismatch')
     tar.commit();print(f'TARGET_COMMIT delta_before={before} deleted={deleted} inserted={inserted} elapsed_seconds={time.monotonic()-beg:.3f}')
   except Exception:tar.rollback();raise
def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=CFG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');x=p.parse_args();check(x.config);a,b=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if x.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={a}..{b}');return
 run(a,b)
if __name__=='__main__':main()
