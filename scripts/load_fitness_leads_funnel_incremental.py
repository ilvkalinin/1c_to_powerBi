#!/usr/bin/env python3
"""Synchronise fitness-leads task facts without invoking the full rebuild."""
from __future__ import annotations
import argparse,json,sys,tempfile,time
from datetime import date,datetime
from pathlib import Path
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.load_fitness_leads_funnel import COLUMNS,TARGETS,br003_horizon,connect_with_retry,copy_source,require_reconciliation
CFG=ROOT/'config/fitness_leads_funnel_incremental.json';STAGE={'task':'_fitness_leads_incremental_task','task_service':'_fitness_leads_incremental_service'};ORDER=('task','task_service')
def cols(n):return tuple(x.strip() for x in COLUMNS[n].split(','))
def config(p):
 x=json.loads(p.read_text());e={'objects':[TARGETS[n] for n in ORDER],'mode':'composite_target_row_diff','timezone':'Europe/Moscow','change_detection':'source_snapshot_to_target_exact_row_multiset_diff','deletion_policy':'delete_target_rows_absent_or_different_in_source_snapshot','no_change_policy':'no_final_target_dml'}
 if any(x.get(k)!=v for k,v in e.items()) or x.get('watermark') is not None or x.get('incremental_sla') is not None:raise RuntimeError('Unexpected incremental config')
def eq(a,b,n):return ' AND '.join(f'{a}.{c} IS NOT DISTINCT FROM {b}.{c}' for c in cols(n))
def delta(c,n):
 x=', '.join(cols(n));c.execute(f'SELECT count(*) FROM ((SELECT {x} FROM {STAGE[n]} EXCEPT ALL SELECT {x} FROM {TARGETS[n]}) UNION ALL (SELECT {x} FROM {TARGETS[n]} EXCEPT ALL SELECT {x} FROM {STAGE[n]})) d');return c.fetchone()[0]
def run(s,e):
 t=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='fitness_leads_incremental_') as d:
  paths,counts,controls=copy_source(s,e,Path(d));target=connect_with_retry('MART_')
  try:
   with target.cursor() as c:
    c.execute('BEGIN');c.execute("SET LOCAL statement_timeout='600s'");c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',('mart.fitness_leads_funnel:incremental',))
    for n in ORDER:
     c.execute('SELECT to_regclass(%s)',(TARGETS[n],));
     if c.fetchone()[0] is None:raise RuntimeError('Incremental refresh requires existing targets')
     c.execute(f'CREATE TEMP TABLE {STAGE[n]} (LIKE {TARGETS[n]} INCLUDING DEFAULTS) ON COMMIT DROP')
     with paths[n].open('rb') as f,c.copy(f"COPY {STAGE[n]} ({', '.join(cols(n))}) FROM STDIN (FORMAT BINARY)") as cp:
      while b:=f.read(1048576):cp.write(b)
     if c.rowcount!=counts[n]:raise RuntimeError('Stage COPY mismatch')
    before={n:delta(c,n) for n in ORDER}
    if not any(before.values()):target.commit();print(f'NO_CHANGES elapsed_seconds={time.monotonic()-t:.3f}');return
    for n in ('task_service','task'):c.execute(f'DELETE FROM {TARGETS[n]} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE[n]} stage WHERE {eq("target","stage",n)})')
    for n in ('task','task_service'):c.execute(f"INSERT INTO {TARGETS[n]} ({', '.join(cols(n))}) SELECT {', '.join('stage.'+x for x in cols(n))} FROM {STAGE[n]} stage WHERE NOT EXISTS (SELECT 1 FROM {TARGETS[n]} target WHERE {eq('target','stage',n)})")
    if any(delta(c,n) for n in ORDER):raise RuntimeError('Pre-commit exact mismatch')
    require_reconciliation(c,counts,controls,s,e);target.commit();print(f'TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic()-t:.3f}')
  except Exception:target.rollback();raise
  finally:target.close()
def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=CFG);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();config(a.config);s,e=br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
 if a.plan_only:print(f'PLAN_OK mode=composite_target_row_diff horizon={s}..{e}');return
 run(s,e)
if __name__=='__main__':main()
