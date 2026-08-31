#!/usr/bin/env python3
"""Run renewal current-state diff then append-only observation history."""
from __future__ import annotations
import argparse,sys
from datetime import date
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.load_renewal_management_contract_incremental import load_config,run as run_parent
from scripts.load_renewal_management_contract_observation import run as append_observation
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--today',type=date.fromisoformat,default=date.today());m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args();load_config(ROOT/'config/renewal_management_incremental.json')
 if a.plan_only:print('PLAN_OK mode=current_state_row_diff_then_append_observation');return
 run_parent(a.today);result=append_observation('append');print(result)
if __name__=='__main__':main()
