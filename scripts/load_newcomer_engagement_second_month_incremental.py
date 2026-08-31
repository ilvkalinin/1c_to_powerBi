#!/usr/bin/env python3
"""Synchronise second-month newcomer fact without invoking full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile,time
from datetime import date,datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_newcomer_engagement_second_month import COLUMNS,TARGET,br003_horizon,config,copy_source_batch,month_batches,source_expected_controls
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/newcomer_engagement_second_month_incremental.json';STAGE='_newcomer_engagement_second_month_incremental_stage'
NAMES=tuple(x.strip() for x in COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def subtract_months(month_start,months):
 absolute=month_start.year*12+month_start.month-1-months;return date(absolute//12,absolute%12+1,1)
def load_config(path):
 actual=json.loads(path.read_text(encoding='utf-8'));expected={'objects':[TARGET],'mode':'bounded_sliding_window','timezone':'Europe/Moscow','months_in_window':2,'change_detection':'source_snapshot_inside_late_change_window','deletion_policy':'atomic_replace_inside_window','outside_window_policy':'preserve_inside_br003_horizon','late_change_evidence':'ASSUMPTION','no_change_policy':'window_replace_even_when_row_counts_match'}
 if any(actual.get(k)!=v for k,v in expected.items()) or actual.get('watermark') is not None or actual.get('incremental_sla') is not None:raise RuntimeError('Unexpected second-month incremental configuration')
 return 2
def boundaries(as_of_date,months):
 horizon_start,end=br003_horizon(as_of_date);current_month=date(as_of_date.year,as_of_date.month,1);return horizon_start,max(horizon_start,subtract_months(current_month,months-1)),end
def controls(cursor,relation,start,end):
 cursor.execute(f"SELECT count(*)::bigint,count(DISTINCT source_row_id)::bigint,count(DISTINCT (contract_id,client_id,month_of_engagement))::bigint,coalesce(sum(second_month_visit_count),0)::bigint,min(month_of_engagement),max(month_of_engagement),count(*) FILTER (WHERE source_row_id IS NULL OR contract_id IS NULL OR client_id IS NULL OR membership_start_date IS NULL OR month_of_engagement IS NULL OR visit_bucket IS NULL OR intro_training_status IS NULL)::bigint,0::bigint FROM {relation} WHERE month_of_engagement >= %s AND month_of_engagement < %s",(start,end));return cursor.fetchone()
def run(start,end):
 started=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='newcomer_second_month_incremental_') as directory:
  with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
   try:
    with source.cursor() as source_cursor,target.cursor() as cursor:
     source_cursor.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');source_cursor.execute("SET LOCAL work_mem='512MB'");cursor.execute('BEGIN');cursor.execute('SELECT to_regclass(%s)',(TARGET,))
     if cursor.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing target')
     cursor.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));cursor.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
     rows=0
     for batch_start,batch_end in month_batches(start,end):
      path=Path(directory)/f'{batch_start:%Y%m}.copy';batch_rows=copy_source_batch(source,batch_start,batch_end,path)
      with path.open('rb') as copied,cursor.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as cp:
       while block:=copied.read(1048576):cp.write(block)
      rows+=batch_rows;path.unlink()
     expected=source_expected_controls(source,start,end);stage=controls(cursor,STAGE,start,end)
     if (stage[0],stage[1],stage[6],stage[7]) != (rows,rows,0,0) or (stage[0],stage[2],stage[3],stage[4],stage[5])!=expected:raise RuntimeError(f'Stage controls failed expected={expected} stage={stage}')
     cursor.execute(f'DELETE FROM {TARGET} WHERE month_of_engagement >= %s AND month_of_engagement < %s',(start,end))
     cursor.execute(f'INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage')
     if cursor.rowcount!=rows:raise RuntimeError('Target window insert differs from source')
     persisted=controls(cursor,TARGET,start,end)
     if persisted!=stage:raise RuntimeError(f'Persisted controls differ stage={stage} persisted={persisted}')
     target.commit();source.rollback();print(f'TARGET_COMMIT window={start}..{end} rows={rows} elapsed_seconds={time.monotonic()-started:.3f}')
   except Exception:target.rollback();source.rollback();raise
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',type=Path,default=CONFIG);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--plan-only',action='store_true');mode.add_argument('--run',action='store_true',help='perform approved target DML');args=parser.parse_args();months=load_config(args.config);horizon_start,start,end=boundaries(datetime.now(ZoneInfo('Europe/Moscow')).date(),months)
 if args.plan_only:print(f'PLAN_OK mode=bounded_sliding_window horizon={horizon_start}..{end} window={start}..{end} late_change_evidence=ASSUMPTION');return
 run(start,end)
if __name__=='__main__':main()
