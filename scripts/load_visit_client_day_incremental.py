#!/usr/bin/env python3
"""Synchronise visit client day without invoking full rebuild."""
from __future__ import annotations
import argparse,json,sys,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_visit_client_day import COLUMNS,TARGET,config,controls,horizon,next_chunk,projection
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/visit_client_day_incremental.json';STAGE='_visit_client_day_incremental_stage';NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 x=json.loads(path.read_text());
 if x.get('objects')!=[TARGET] or x.get('mode')!='target_row_diff' or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected visit client day incremental configuration')
def delta(c):
 c.execute(f'SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET}) UNION ALL (SELECT {SELECTED} FROM {TARGET} EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d');return c.fetchone()[0]
def run(start,end):
 started=time.monotonic()
 with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
  try:
   with source.cursor() as s,target.cursor() as c:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');c.execute('BEGIN');c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP');chunk_start=start;copied=0
    while chunk_start<end:
     chunk_end=next_chunk(chunk_start,end,6);query=projection(chunk_start,chunk_end)
     with s.copy(f'COPY ({query}) TO STDOUT WITH (FORMAT BINARY)') as sc,c.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc:
      while block:=sc.read():tc.write(block)
     if s.rowcount!=c.rowcount:raise RuntimeError('Source/stage COPY mismatch')
     copied+=s.rowcount;chunk_start=chunk_end
    stage=controls(c,STAGE)
    if not stage[0] or stage[-1] or stage[0]!=copied:raise RuntimeError('Stage controls failed')
    before=delta(c)
    if not before:target.commit();source.rollback();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
    c.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})');c.execute(f'INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE {EQUALITY})')
    if delta(c):raise RuntimeError('Pre-commit exact mismatch')
    if controls(c,TARGET)!=stage:raise RuntimeError('Persisted controls differ')
    target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
  except Exception:target.rollback();source.rollback();raise
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();load_config(a.config);start,end=horizon()
 if a.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
