#!/usr/bin/env python3
"""Synchronise administrator card Gymmy daily fact without full rebuild."""
from __future__ import annotations
import argparse,json,sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_administrator_card_gymmy_daily import COLUMNS,EXTRACT,assert_card_mapping,br003_horizon,connect_with_retry,rendered,source_direction_totals,target_direction_totals,SOURCE_CONTROLS
CONFIG=ROOT/'config/administrator_card_gymmy_daily_incremental.json';TARGET='mart.administrator_card_gymmy_daily';STAGE='_administrator_card_gymmy_daily_incremental_stage';N=tuple(x.strip() for x in COLUMNS.split(','));COL=', '.join(N);SCOL=', '.join('stage.'+x for x in N);EQ=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in N)
def config_ok(path):
 x=json.loads(path.read_text());
 if x.get('objects')!=[TARGET] or x.get('mode')!='target_row_diff' or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected Gymmy incremental configuration')
def delta(c):
 c.execute(f'SELECT count(*) FROM ((SELECT {COL} FROM {STAGE} EXCEPT ALL SELECT {COL} FROM {TARGET}) UNION ALL (SELECT {COL} FROM {TARGET} EXCEPT ALL SELECT {COL} FROM {STAGE})) d');return c.fetchone()[0]
def run(start,end):
 with connect_with_retry('SOURCE_') as source,connect_with_retry('MART_') as target:
  try:
   with source.cursor() as s,target.cursor() as c:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');s.execute('SET LOCAL enable_seqscan=off');assert_card_mapping(s);expected=source_direction_totals(s,rendered(SOURCE_CONTROLS,start,end))
    c.execute('BEGIN');c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
    with c.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc,s.copy(f'COPY ({rendered(EXTRACT,start,end)}) TO STDOUT WITH (FORMAT BINARY)') as sc:
     for b in sc:tc.write(b)
    before=delta(c)
    if not before:target.commit();source.rollback();print('NO_CHANGES');return
    c.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQ})');c.execute(f'INSERT INTO {TARGET} ({COL}) SELECT {SCOL} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE {EQ})')
    if delta(c):raise RuntimeError('Pre-commit exact mismatch')
    if target_direction_totals(c,TARGET)!=expected:raise RuntimeError('Persisted direction controls differ')
    target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before}')
  except Exception:target.rollback();source.rollback();raise
def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();config_ok(a.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
