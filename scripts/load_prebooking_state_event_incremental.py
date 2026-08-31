#!/usr/bin/env python3
"""Synchronise prebooking state events without invoking the full rebuild."""
from __future__ import annotations
import argparse,json,sys,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_prebooking_state_event import COLUMNS,br003_horizon,config,controls,extract_sql,source_controls,source_controls_sql
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/prebooking_state_event_incremental.json';TARGET='mart.prebooking_state_event';STAGE='_prebooking_state_event_incremental_stage';NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 actual=json.loads(path.read_text(encoding='utf-8'));expected={'objects':[TARGET],'mode':'target_row_diff','timezone':'Europe/Moscow','change_detection':'source_snapshot_to_target_exact_row_multiset_diff','deletion_policy':'delete_target_rows_absent_or_different_in_source_snapshot','no_change_policy':'no_final_target_dml'}
 if any(actual.get(k)!=v for k,v in expected.items()) or actual.get('watermark') is not None or actual.get('incremental_sla') is not None:raise RuntimeError('Unexpected prebooking incremental configuration')
def delta(cursor):
 cursor.execute(f'SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET}) UNION ALL (SELECT {SELECTED} FROM {TARGET} EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d');return cursor.fetchone()[0]
def run(start,end):
 started=time.monotonic();query=extract_sql(start,end);control_query=source_controls_sql(start,end)
 with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
  try:
   with source.cursor() as s,target.cursor() as t:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');t.execute('BEGIN');t.execute('SELECT to_regclass(%s)',(TARGET,))
    if t.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing target')
    t.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));expected=source_controls(s,control_query)
    if not expected[0]:raise RuntimeError('Unexpected empty source projection')
    t.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
    with t.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc,s.copy(f'COPY ({query}) TO STDOUT WITH (FORMAT BINARY)') as sc:
     for block in sc:tc.write(block)
    if controls(t,STAGE)!=expected:raise RuntimeError('Source and staged controls differ')
    before=delta(t)
    if not before:target.commit();source.rollback();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
    t.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})')
    t.execute(f'INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE {EQUALITY})')
    if delta(t):raise RuntimeError('Pre-commit exact mismatch')
    if controls(t,TARGET)!=expected:raise RuntimeError('Persisted controls differ from source')
    target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
  except Exception:target.rollback();source.rollback();raise
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',type=Path,default=CONFIG);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--plan-only',action='store_true');mode.add_argument('--run',action='store_true',help='perform approved target DML');args=parser.parse_args();load_config(args.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if args.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
