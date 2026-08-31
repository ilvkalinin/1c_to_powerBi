#!/usr/bin/env python3
"""Synchronise group lesson without invoking full rebuild."""
from __future__ import annotations
import argparse,json,sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_group_lesson import COLUMNS,EXTRACT,CONTROLS,base_controls,br003_horizon,connect_with_retry,rendered,target_controls
CONFIG=ROOT/'config/group_lesson_incremental.json';TARGET='mart.group_lesson';SRC='_group_lesson_incremental_source';STG='_group_lesson_incremental_stage'
N=('group_lesson_id','lesson_created_at','lesson_start_at','lesson_end_at','club_id','activity_id','employee_id','service_id','capacity','is_free_program','active_booking_count','arrived_count','free_program_arrived_count');COL=', '.join(N);SCOL=', '.join('s.'+x for x in N);EQ=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in N)
def config_ok(path):
 x=json.loads(path.read_text());
 if x.get('objects')!=[TARGET] or x.get('mode')!='target_row_diff' or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected group lesson incremental configuration')
def delta(c):
 c.execute(f'SELECT count(*) FROM ((SELECT {COL} FROM {STG} EXCEPT ALL SELECT {COL} FROM {TARGET}) UNION ALL (SELECT {COL} FROM {TARGET} EXCEPT ALL SELECT {COL} FROM {STG})) d');return c.fetchone()[0]
def run(start,end):
 extract,control=rendered(EXTRACT,start,end),rendered(CONTROLS,start,end)
 with connect_with_retry('SOURCE_') as source,connect_with_retry('MART_') as target:
  try:
   with source.cursor() as s,target.cursor() as c:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');expected=base_controls(s,control)
    c.execute('BEGIN');c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));c.execute(f'CREATE TEMP TABLE {SRC} (group_lesson_id text NOT NULL,lesson_created_at timestamp NOT NULL,lesson_start_at timestamp NOT NULL,lesson_end_at timestamp NOT NULL,club_id text NOT NULL,activity_id text,employee_id text NOT NULL,service_id text NOT NULL,capacity integer,is_free_program boolean NOT NULL,free_program_arrived_count integer NOT NULL) ON COMMIT DROP');c.execute(f'CREATE TEMP TABLE {STG} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
    with c.copy(f'COPY {SRC} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc,s.copy(f'COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)') as sc:
     for b in sc:tc.write(b)
    c.execute(f"INSERT INTO {STG} ({COL}) WITH state_per_lesson AS (SELECT booking_document_id group_lesson_id,coalesce(sum(booking_delta),0)::bigint active_booking_count,nullif(count(*) FILTER (WHERE state_order=4),0)::bigint paid_arrived_count FROM mart.prebooking_state_event WHERE booking_kind='GZ' GROUP BY 1) SELECT s.group_lesson_id,s.lesson_created_at,s.lesson_start_at,s.lesson_end_at,s.club_id,s.activity_id,s.employee_id,s.service_id,s.capacity,s.is_free_program,coalesce(st.active_booking_count,0),coalesce(st.paid_arrived_count,s.free_program_arrived_count,0),s.free_program_arrived_count FROM {SRC} s LEFT JOIN state_per_lesson st USING(group_lesson_id)")
    c.execute(f'SELECT count(*) FROM {STG}')
    if c.fetchone()[0]!=expected[0]:raise RuntimeError('Derived stage cardinality differs')
    before=delta(c)
    if not before:target.commit();source.rollback();print('NO_CHANGES');return
    c.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STG} stage WHERE {EQ})');c.execute(f'INSERT INTO {TARGET} ({COL}) SELECT {SCOL} FROM {STG} s WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE '+ ' AND '.join(f'target.{x} IS NOT DISTINCT FROM s.{x}' for x in N)+')')
    if delta(c):raise RuntimeError('Pre-commit exact mismatch')
    if target_controls(c)!=expected:raise RuntimeError('Persisted controls differ')
    target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before}')
  except Exception:target.rollback();source.rollback();raise
def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();config_ok(a.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
