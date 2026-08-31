#!/usr/bin/env python3
"""Run revenue incremental runners in dependency order."""
from __future__ import annotations
import argparse,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
STAGES=('load_dpfu_ancillary_revenue_incremental.py','load_reception_revenue_incremental.py','load_ip_revenue_daily_incremental.py','load_revenue_group_summary_incremental.py')
def main():
 p=argparse.ArgumentParser();m=p.add_mutually_exclusive_group(required=True);m.add_argument('--plan-only',action='store_true');m.add_argument('--run',action='store_true');a=p.parse_args()
 if a.plan_only:print('PLAN_OK mode=ordered_scoped_diffs_then_summary_diff');return
 for script in STAGES:subprocess.run([sys.executable,str(ROOT/'scripts'/script),'--run'],cwd=ROOT,check=True)
if __name__=='__main__':main()
