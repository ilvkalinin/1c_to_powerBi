#!/usr/bin/env python3
"""Atomically create or append the approved forward renewal observation fact."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import date, datetime
from pathlib import Path
from typing import Any

import psycopg

from load_renewal_management_contract import config
from mart_connection import connect_with_retry


ROOT = Path(__file__).resolve().parents[1]
TARGET = "mart.renewal_management_contract_observation"
DDL = ROOT / "sql/marts/renewal_management_contract_observation_ddl.sql"
EXTRACT = ROOT / "sql/marts/renewal_management_contract_observation_extract.sql"
APPEND = ROOT / "sql/marts/renewal_management_contract_observation_append.sql"
SOURCE_CONTROLS = ROOT / "sql/marts/renewal_management_contract_observation_source_controls.sql"
RECONCILIATION = ROOT / "sql/tests/renewal_management_contract_observation_reconciliation.sql"


def json_default(value: Any) -> Any:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(f"Unsupported JSON value: {type(value)!r}")


def ddl_without_transaction() -> str:
    text = DDL.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^BEGIN;\s*", "", text, count=1)
    text = re.sub(r"(?m)^COMMIT;\s*$", "", text, count=1)
    if f"CREATE TABLE {TARGET}" not in text:
        raise RuntimeError("Unexpected observation DDL")
    return text


def append_sql() -> str:
    template = APPEND.read_text(encoding="utf-8")
    extract = EXTRACT.read_text(encoding="utf-8").strip().rstrip(";")
    if template.count("{{CURRENT_STATE_EXTRACT}}") != 1:
        raise RuntimeError("Observation append template must contain one extract placeholder")
    return template.replace("{{CURRENT_STATE_EXTRACT}}", extract)


def relation_exists(cursor) -> bool:
    cursor.execute("SELECT to_regclass(%s) IS NOT NULL", (TARGET,))
    return cursor.fetchone()[0]


def source_controls(cursor) -> tuple[Any, ...]:
    cursor.execute(SOURCE_CONTROLS.read_text(encoding="utf-8").strip().rstrip(";"))
    result = cursor.fetchone()
    if result is None or result[0] is None:
        raise RuntimeError("Independent parent-mart controls returned no result")
    if result[-1] != 0:
        raise RuntimeError(f"Parent mart violates observation input contract: {result}")
    return result


def reconciliation_statements(expected: tuple[Any, ...]) -> list[str]:
    values = {
        "$1::bigint": str(expected[0]),
        "$2::bigint": str(expected[1]),
        "$3::date": f"DATE '{expected[2].isoformat()}'",
        "$4::date": f"DATE '{expected[3].isoformat()}'",
    }
    text = RECONCILIATION.read_text(encoding="utf-8")
    for token, replacement in values.items():
        text = text.replace(token, replacement)
    return [part.strip().rstrip(";") for part in re.split(r"(?m)(?=-- RMO-R\d+)", text)
            if part.strip().startswith("-- RMO-R")]


def require_reconciliation(cursor, expected: tuple[Any, ...]) -> None:
    statements = reconciliation_statements(expected)
    if len(statements) != 5:
        raise RuntimeError(f"Unexpected observation reconciliation count: {len(statements)}")
    results = []
    for ordinal, statement in enumerate(statements, start=1):
        cursor.execute(statement)
        row = cursor.fetchone()
        results.append(row)
        print(f"RECONCILIATION_CONTROL_DONE id=RMO-R{ordinal:02d}", flush=True)
    if not results[0][-1] or any(results[1]) or any(results[2]) or any(results[3]) or any(results[4]):
        raise RuntimeError(f"Observation reconciliation failed: {results}")


def run(mode: str) -> dict[str, Any]:
    connection = connect_with_retry(
        lambda: psycopg.connect(**config("MART_")), endpoint="mart"
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ")
            cursor.execute("SELECT set_config('statement_timeout', '180000', true)")
            cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TARGET + ":append",))
            exists = relation_exists(cursor)
            if mode == "apply":
                if exists:
                    raise RuntimeError(f"Initial apply requires absent target: {TARGET}")
                cursor.execute(ddl_without_transaction())
                print("TARGET_DDL_READY", flush=True)
            elif not exists:
                raise RuntimeError(f"Append requires existing target: {TARGET}")

            expected = source_controls(cursor)
            cursor.execute("SELECT clock_timestamp()")
            observed_at = cursor.fetchone()[0]
            cursor.execute(append_sql(), (observed_at,))
            inserted_kinds = Counter(row[0] for row in cursor.fetchall())
            require_reconciliation(cursor, expected)
            connection.commit()
            print("TARGET_COMMIT_PASS", flush=True)
            return {
                "mode": mode,
                "observed_at": observed_at,
                "parent_expected_rows": expected[0],
                "parent_expected_distinct_contracts": expected[1],
                "inserted": dict(sorted(inserted_kinds.items())),
            }
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apply", action="store_true", help="approved initial DDL and baseline append")
    group.add_argument("--append", action="store_true", help="approved later delta append")
    args = parser.parse_args()
    result = run("apply" if args.apply else "append")
    print(json.dumps(result, ensure_ascii=False, default=json_default, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
