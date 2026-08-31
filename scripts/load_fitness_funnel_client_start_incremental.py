#!/usr/bin/env python3
"""Synchronise fitness-funnel client starts without the guarded full rebuild."""
from __future__ import annotations
import argparse, json, sys, time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
from scripts.load_fitness_funnel_client_start import COLUMNS,TABLE,export_derived_snapshot,reconciliation_sql,target_connection
CONFIG=ROOT/'config/fitness_funnel_client_start_incremental.json'; STAGE='_fitness_funnel_client_start_incremental_stage'; COL=tuple(x.strip() for x in COLUMNS.split(','))
def config(path):
 p=json.loads(path.read_text()); e={'object':TABLE,'mode':'target_row_diff','timezone':'Europe/Moscow','change_detection':'source_snapshot_to_target_exact_row_diff','deletion_policy':'delete_target_rows_absent_or_different_in_source_snapshot','no_change_policy':'no_final_target_dml'}
 if any(p.get(k)!=v for k,v in e.items()) or p.get('watermark') is not None or p.get('incremental_sla') is not None: raise RuntimeError('Unexpected incremental config')
def equal(a,b): return ' AND '.join(f'{a}.{x} IS NOT DISTINCT FROM {b}.{x}' for x in COL)
def delta(c):
 x=', '.join(COL); c.execute(f'SELECT count(*) FROM ((SELECT {x} FROM {STAGE} EXCEPT ALL SELECT {x} FROM {TABLE}) UNION ALL (SELECT {x} FROM {TABLE} EXCEPT ALL SELECT {x} FROM {STAGE})) d'); return c.fetchone()[0]
def run(start,end,cap):
 t=time.monotonic(); path,controls=export_derived_snapshot(start,end,cap); target=None
 try:
  target=target_connection('fitness_funnel_client_start_incremental_target')
  with target.cursor() as c:
   c.execute('BEGIN'); c.execute("SET LOCAL statement_timeout='300s'"); c.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(TABLE+':incremental',)); c.execute('SELECT to_regclass(%s)',(TABLE,))
   if c.fetchone()[0] is None: raise RuntimeError('Incremental refresh requires the existing target')
   c.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP')
   with path.open('rb') as f,c.copy(f"COPY {STAGE} ({', '.join(COL)}) FROM STDIN (FORMAT BINARY)") as cp:
    while b:=f.read(1048576): cp.write(b)
   c.execute(f'ALTER TABLE {STAGE} RENAME TO _fitness_funnel_client_start_stage'); c.execute(reconciliation_sql(controls['FF-S03']));
   if [r for r in c.fetchall() if r[4]!='PASS']: raise RuntimeError('Stage reconciliation failed')
   c.execute('ALTER TABLE _fitness_funnel_client_start_stage RENAME TO '+STAGE); before=delta(c)
   if not before: target.commit(); print(f'NO_CHANGES elapsed_seconds={time.monotonic()-t:.3f}'); return
   c.execute(f'DELETE FROM {TABLE} target WHERE NOT EXISTS (SELECT 1 FROM {STAGE} stage WHERE {equal("target","stage")})'); deleted=c.rowcount
   c.execute(f"INSERT INTO {TABLE} ({', '.join(COL)}) SELECT {', '.join('stage.'+x for x in COL)} FROM {STAGE} stage WHERE NOT EXISTS (SELECT 1 FROM {TABLE} target WHERE {equal('target','stage')})"); inserted=c.rowcount
   if delta(c): raise RuntimeError('Pre-commit exact source/target mismatch')
   c.execute(reconciliation_sql(controls['FF-S03']));
   if [r for r in c.fetchall() if r[4]!='PASS']: raise RuntimeError('Target reconciliation failed')
   target.commit(); print(f'TARGET_COMMIT delta_before={before} deleted={deleted} inserted={inserted} elapsed_seconds={time.monotonic()-t:.3f}')
 except Exception:
  if target: target.rollback()
  raise
 finally:
  if target: target.close()
  path.unlink(missing_ok=True)
def main():
 p=argparse.ArgumentParser(); p.add_argument('--config',type=Path,default=CONFIG); m=p.add_mutually_exclusive_group(required=True); m.add_argument('--plan-only',action='store_true'); m.add_argument('--run',action='store_true'); p.add_argument('--start',type=date.fromisoformat,default=date(2024,1,1)); p.add_argument('--end',type=date.fromisoformat,default=datetime.now(ZoneInfo('Europe/Moscow')).date()); p.add_argument('--max-derived-bytes',type=int,default=1000000000); a=p.parse_args(); config(a.config)
 if a.start>=a.end or a.max_derived_bytes<=0: raise SystemExit('invalid horizon or cap')
 if a.plan_only: print(f'PLAN_OK mode=target_row_diff horizon={a.start}..{a.end}'); return
 run(a.start,a.end,a.max_derived_bytes)
if __name__=='__main__': main()
