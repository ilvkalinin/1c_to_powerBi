#!/usr/bin/env python3
"""Run parent renewal refresh, then append observation only after parent success."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import psycopg

from load_renewal_management_contract import config
from mart_connection import connect_with_retry


ROOT = Path(__file__).resolve().parents[1]
TARGET = "mart.renewal_management_observation_run"
DDL = ROOT / "sql/marts/renewal_management_observation_run_ddl.sql"
RECONCILIATION = ROOT / "sql/tests/renewal_management_observation_run_reconciliation.sql"


def now() -> datetime:
    connection = connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart")
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT clock_timestamp()")
            return cursor.fetchone()[0]
    finally:
        connection.close()


def ddl_without_transaction() -> str:
    text = DDL.read_text(encoding="utf-8")
    return text.replace("BEGIN;", "", 1).replace("COMMIT;", "", 1)


def bootstrap() -> None:
    connection = connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart")
    try:
        with connection.cursor() as cursor:
            cursor.execute("BEGIN")
            cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET,))
            cursor.execute("SELECT to_regclass(%s) IS NOT NULL", (TARGET,))
            if cursor.fetchone()[0]:
                raise RuntimeError(f"Initial bootstrap requires absent target: {TARGET}")
            cursor.execute(ddl_without_transaction())
            cursor.execute(RECONCILIATION.read_text(encoding="utf-8").strip().rstrip(";"))
            if any(cursor.fetchone()):
                raise RuntimeError("Journal bootstrap reconciliation failed")
            connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def start_run(started_at: datetime) -> int:
    connection = connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart")
    try:
        with connection.cursor() as cursor:
            cursor.execute("INSERT INTO mart.renewal_management_observation_run (started_at, status) VALUES (%s, 'RUNNING') RETURNING run_id", (started_at,))
            run_id = cursor.fetchone()[0]
            connection.commit()
            return run_id
    finally:
        connection.close()


def finish_run(run_id: int, status: str, parent_code: int | None, observation_code: int | None, counts: dict[str, int]) -> None:
    connection = connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart")
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                "UPDATE mart.renewal_management_observation_run "
                "SET finished_at = clock_timestamp(), status = %s, parent_exit_code = %s, observation_exit_code = %s, "
                "baseline_rows = %s, changed_rows = %s, removed_rows = %s WHERE run_id = %s AND status = 'RUNNING'",
                (status, parent_code, observation_code, counts.get("BASELINE", 0), counts.get("CHANGED", 0), counts.get("REMOVED", 0), run_id),
            )
            if cursor.rowcount != 1:
                raise RuntimeError("Journal lifecycle update did not affect one RUNNING row")
            cursor.execute(RECONCILIATION.read_text(encoding="utf-8").strip().rstrip(";"))
            if any(cursor.fetchone()):
                raise RuntimeError("Journal reconciliation failed")
            connection.commit()
    finally:
        connection.close()


def invoke(command: list[str], timeout_seconds: int) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False,
                          timeout=timeout_seconds)


def parse_observation(stdout: str) -> dict[str, int]:
    for line in reversed(stdout.splitlines()):
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload.get("inserted"), dict):
            return {str(key): int(value) for key, value in payload["inserted"].items()}
    raise RuntimeError("Observation runner produced no terminal counts JSON")


def run(simulate_parent_failure: bool, parent_timeout_seconds: int) -> int:
    run_id = start_run(now())
    if simulate_parent_failure:
        finish_run(run_id, "FAILED_PARENT", 1, None, {})
        print(json.dumps({"run_id": run_id, "status": "FAILED_PARENT", "observation_invoked": False}))
        return 1
    try:
        parent = invoke([sys.executable, "scripts/load_renewal_management_contract.py", "--rebuild"], parent_timeout_seconds)
    except subprocess.TimeoutExpired:
        finish_run(run_id, "FAILED_PARENT", 124, None, {})
        print(json.dumps({"run_id": run_id, "status": "FAILED_PARENT", "observation_invoked": False}))
        return 1
    if parent.returncode != 0 or "TARGET_COMMIT_PASS" not in parent.stdout:
        finish_run(run_id, "FAILED_PARENT", parent.returncode, None, {})
        print(json.dumps({"run_id": run_id, "status": "FAILED_PARENT", "observation_invoked": False}))
        return 1
    observation = invoke([sys.executable, "scripts/load_renewal_management_contract_observation.py", "--append"], 180)
    if observation.returncode != 0:
        finish_run(run_id, "FAILED_OBSERVATION", parent.returncode, observation.returncode, {})
        print(json.dumps({"run_id": run_id, "status": "FAILED_OBSERVATION", "observation_invoked": True}))
        return 1
    counts = parse_observation(observation.stdout)
    finish_run(run_id, "SUCCEEDED", parent.returncode, observation.returncode, counts)
    print(json.dumps({"run_id": run_id, "status": "SUCCEEDED", "observation_invoked": True, "inserted": counts}, ensure_ascii=False, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap-journal", action="store_true")
    parser.add_argument("--simulate-parent-failure", action="store_true")
    parser.add_argument("--parent-timeout-seconds", type=int, default=480)
    args = parser.parse_args()
    if args.bootstrap_journal:
        bootstrap()
        print(json.dumps({"journal": "BOOTSTRAPPED"}))
        return 0
    if args.parent_timeout_seconds < 1:
        parser.error("--parent-timeout-seconds must be positive")
    return run(args.simulate_parent_failure, args.parent_timeout_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
