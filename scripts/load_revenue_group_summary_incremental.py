#!/usr/bin/env python3
"""Synchronise revenue group summary without invoking full rebuild."""
from __future__ import annotations
import argparse,json,sys,time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_revenue_group_summary import REUSED_ARTICLES,SOURCE_COLUMNS,SOURCE_ONLY_ARTICLES,TARGET_COLUMNS,br003_horizon,config,controls,direct_source_extract,require_source_equivalence,require_stage_integrity
from scripts.mart_connection import connect_with_retry
CONFIG=ROOT/'config/revenue_refresh_chain_incremental.json';TARGET='mart.revenue_group_summary_daily';SOURCE_STAGE='_revenue_group_summary_source_stage';REUSED_STAGE='_revenue_group_summary_reused_stage';STAGE='_revenue_group_summary_stage';NAMES=tuple(x.strip() for x in TARGET_COLUMNS.split(','));SELECTED=', '.join(NAMES);STAGE_SELECTED=', '.join('stage.'+x for x in NAMES);EQUALITY=' AND '.join(f'target.{x} IS NOT DISTINCT FROM stage.{x}' for x in NAMES)
def load_config(path):
 x=json.loads(path.read_text());
 if x.get('mode')!='ordered_scoped_diffs_then_summary_diff' or x.get('objects')!=['mart.ancillary_revenue_movement','mart.ip_revenue_daily',TARGET] or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected revenue chain incremental configuration')
def delta(c):
 c.execute(f'SELECT count(*) FROM ((SELECT {SELECTED} FROM {STAGE} EXCEPT ALL SELECT {SELECTED} FROM {TARGET}) UNION ALL (SELECT {SELECTED} FROM {TARGET} EXCEPT ALL SELECT {SELECTED} FROM {STAGE})) d');return c.fetchone()[0]
def run(start,end):
 started=time.monotonic();extract=direct_source_extract(start,end)
 with connect_with_retry(lambda:psycopg.connect(**config('SOURCE_')),endpoint='source') as source,connect_with_retry(lambda:psycopg.connect(**config('MART_')),endpoint='mart') as target:
  try:
   with source.cursor() as s,target.cursor() as c:
    s.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY');c.execute('BEGIN');c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TARGET+':incremental',));c.execute(f'CREATE TEMP TABLE {SOURCE_STAGE} (source_branch text NOT NULL,revenue_date date NOT NULL,club_id text NOT NULL,revenue_article_code text NOT NULL,revenue_amount numeric(18,2) NOT NULL) ON COMMIT DROP');c.execute(f'CREATE TEMP TABLE {REUSED_STAGE} (revenue_date date NOT NULL,club_id text NOT NULL,revenue_article_code text NOT NULL,revenue_amount numeric(18,2) NOT NULL) ON COMMIT DROP');c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
    with c.copy(f'COPY {SOURCE_STAGE} ({SOURCE_COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as tc,s.copy(f'COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)') as sc:
     for block in sc:tc.write(block)
    c.execute("INSERT INTO "+REUSED_STAGE+" SELECT service_date,club_id,'03.ДПФУ (ШТАТ)',sum(revenue_amount)::numeric(18,2) FROM mart.ancillary_revenue_movement WHERE revenue_scope='dpfu' AND service_date >= %s AND service_date < %s AND club_id IS NOT NULL GROUP BY 1,2 UNION ALL SELECT revenue_date,club_id,'04.ДПФУ (АРЕНДА ИП)',sum(revenue_amount)::numeric(18,2) FROM mart.ip_revenue_daily WHERE revenue_date >= %s AND revenue_date < %s AND club_id IS NOT NULL GROUP BY 1,2 UNION ALL SELECT service_date,club_id,'05.РЕЦЕПЦИЯ',sum(revenue_amount)::numeric(18,2) FROM mart.ancillary_revenue_movement WHERE revenue_scope='reception' AND service_date >= %s AND service_date < %s AND club_id IS NOT NULL GROUP BY 1,2",(start,end,start,end,start,end))
    if set(controls(c,REUSED_STAGE,'revenue_article_code'))!=set(REUSED_ARTICLES):raise RuntimeError('Expected reused articles missing')
    c.execute(f"INSERT INTO {STAGE} ({TARGET_COLUMNS}) SELECT revenue_date,club_id,revenue_article_code,sum(revenue_amount)::numeric(18,2) FROM (SELECT revenue_date,club_id,revenue_article_code,revenue_amount FROM {SOURCE_STAGE} WHERE revenue_article_code=ANY(%s) UNION ALL SELECT revenue_date,club_id,revenue_article_code,revenue_amount FROM {REUSED_STAGE}) rows GROUP BY 1,2,3",(list(SOURCE_ONLY_ARTICLES),))
    require_stage_integrity(c);require_source_equivalence(c);stage_controls=controls(c,STAGE,'revenue_article_code');before=delta(c)
    if not before:target.commit();source.rollback();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-started:.3f}');return
    c.execute(f'DELETE FROM {TARGET} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {EQUALITY})');c.execute(f'INSERT INTO {TARGET} ({SELECTED}) SELECT {STAGE_SELECTED} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGET} target WHERE {EQUALITY})')
    if delta(c):raise RuntimeError('Pre-commit exact mismatch')
    if controls(c,TARGET,'revenue_article_code')!=stage_controls:raise RuntimeError('Persisted controls differ')
    target.commit();source.rollback();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-started:.3f}')
  except Exception:target.rollback();source.rollback();raise
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',type=Path,default=CONFIG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();load_config(a.config);start,end=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=target_row_diff horizon={start}..{end}');return
 run(start,end)
if __name__=='__main__':main()
