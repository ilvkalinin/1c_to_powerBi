#!/usr/bin/env python3
"""Run the approved revenue refresh dependency chain fail-closed."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
JOURNAL = ROOT / "docs/reports/revenue_refresh_chain_runs.tsv"
STAGES = (
    ("dpfu", ROOT / "scripts/load_dpfu_ancillary_revenue.py"),
    ("reception", ROOT / "scripts/load_reception_revenue.py"),
    ("ip", ROOT / "scripts/load_ip_revenue_daily.py"),
    ("summary", ROOT / "scripts/load_revenue_group_summary.py"),
)


def control_line(output: str) -> str:
    for line in reversed(output.splitlines()):
        if line.startswith(("DML_COMMITTED", "TARGET_CONTROL", "STAGE_PASS")):
            return line.replace("\t", " ")
    return "-"


def append_journal(run_id: str, label: str, stage: str, seconds: float, status: str, control: str) -> None:
    with JOURNAL.open("a", encoding="utf-8") as journal:
        journal.write(f"{run_id}\t{label}\t{stage}\t{seconds:.2f}\t{status}\t{control}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="initial", help="journal label for this full run")
    args = parser.parse_args()
    run_id = datetime.now(ZoneInfo("Europe/Moscow")).isoformat(timespec="seconds")
    started = time.monotonic()
    print(f"CHAIN_STARTED run_id={run_id} label={args.label}", flush=True)

    for stage, script in STAGES:
        stage_started = time.monotonic()
        print(f"CHAIN_STAGE_STARTED stage={stage}", flush=True)
        result = subprocess.run(
            [sys.executable, str(script), "--apply"],
            cwd=ROOT,
            env=os.environ.copy(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        output = result.stdout or ""
        if output:
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
        seconds = time.monotonic() - stage_started
        status = "PASS" if result.returncode == 0 else f"FAIL:{result.returncode}"
        append_journal(run_id, args.label, stage, seconds, status, control_line(output))
        print(f"CHAIN_STAGE_FINISHED stage={stage} seconds={seconds:.2f} status={status}", flush=True)
        if result.returncode:
            print(f"CHAIN_FAILED stage={stage}; downstream stages were not started", flush=True)
            raise SystemExit(result.returncode)

    print(f"CHAIN_COMMITTED run_id={run_id} seconds={time.monotonic() - started:.2f} stages=4", flush=True)


if __name__ == "__main__":
    main()
