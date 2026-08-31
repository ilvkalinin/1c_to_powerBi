#!/usr/bin/env python3
"""Synchronise minimal newcomer and guest date facts without full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_newcomer_guest_visits_minimal_date_facts import COLUMNS,TARGETS,br003_horizon,config,copy_source,require_reconciliation
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/newcomer_guest_visits_incremental.json';ORDER=('first_visit','guest_visit_conversion');STAGES={name:f'_newcomer_guest_{name}_incremental_stage' for name in ORDER}
def names(name):return tuple(x.strip() for x in COLUMNS[name].split(','))
def load_config(path):
 actual=json.loads(path.read_text(encoding='utf-8'));expected={'objects':[TARGETS[n] for n in ORDER],'mode':'composite_target_row_diff','timezone':'Europe/Moscow','change_detection':'source_snapshot_to_target_exact_row_multiset_diff','deletion_policy':'delete_target_rows_absent_or_different_in_source_snapshot','no_change_policy':'no_final_target_dml'}
 if any(actual.get(k)!=v for k,v in expected.items()) or actual.get('watermark') is not None or actual.get('incremental_sla') is not None:raise RuntimeError('Unexpected newcomer guest incremental configuration')
def equality(name):return ' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in names(name))
def delta(cursor,name):
 selected=', '.join(names(name));cursor.execute(f'SELECT count(*) FROM ((SELECT {selected} FROM {STAGES[name]} EXCEPT ALL SELECT {selected} FROM {TARGETS[name]}) UNION ALL (SELECT {selected} FROM {TARGETS[name]} EXCEPT ALL SELECT {selected} FROM {STAGES[name]})) d');return cursor.fetchone()[0]
def sync(cursor,name):
 selected=', '.join(names(name));stage_selected=', '.join('stage.'+x for x in names(name));match=equality(name)
 cursor.execute(f'DELETE FROM {TARGETS[name]} target WHERE NOT EXISTS (SELECT 1 FROM {STAGES[name]} stage WHERE {match})')
 cursor.execute(f'INSERT INTO {TARGETS[name]} ({selected}) SELECT {stage_selected} FROM {STAGES[name]} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGETS[name]} target WHERE {match})')
def run(start,end):
 started=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='newcomer_guest_incremental_') as directory:
  paths,counts=copy_source(start,end,Path(directory))
  with connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
   try:
    with target.cursor() as cursor:
     cursor.execute('BEGIN');cursor.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',('mart.newcomer_guest_visits:incremental',))
     for name in ORDER:
      cursor.execute('SELECT to_regclass(%s)',(TARGETS[name],))
      if cursor.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing targets')
      cursor.execute(f'CREATE TEMP TABLE {STAGES[name]} (LIKE {TARGETS[name]} INCLUDING DEFAULTS) ON COMMIT DROP')
      with paths[name].open('rb') as source,cursor.copy(f'COPY {STAGES[name]} ({COLUMNS[name]}) FROM STDIN WITH (FORMAT BINARY)') as cp:
       while block:=source.read(1048576):cp.write(block)
     before={name:delta(cursor,name) for name in ORDER}
     if not any(before.values()):target.commit();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
     for name in ORDER:sync(cursor,name)
     if any(delta(cursor,name) for name in ORDER):raise RuntimeError('Pre-commit exact mismatch')
     require_reconciliation(cursor,counts,start,end);target.commit();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
   except Exception:target.rollback();raise
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',type=Path,default=CONFIG);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--plan-only',action='store_true');mode.add_argument('--run',action='store_true',help='perform approved target DML');args=parser.parse_args();load_config(args.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if args.plan_only:print(f'PLAN_OK mode=composite_target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
