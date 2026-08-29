#!/usr/bin/env python3
"""Measure the reviewed latest-as-of read of the renewal observation fact."""

from __future__ import annotations

import json
from datetime import date, datetime
from typing import Any

import psycopg

from load_renewal_management_contract import config
from mart_connection import connect_with_retry


TARGET = "mart.renewal_management_contract_observation"
DISTINCT_ON_QUERY = """
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
WITH latest AS (
    SELECT DISTINCT ON (expiring_contract_id)
        expiring_contract_id, observation_kind
    FROM mart.renewal_management_contract_observation
    WHERE observed_at <= %s::timestamptz
    ORDER BY expiring_contract_id, observed_at DESC
)
SELECT count(*) FILTER (WHERE observation_kind <> 'REMOVED')
FROM latest
"""

GROUPED_MAX_QUERY = """
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
WITH latest_time AS (
    SELECT expiring_contract_id, max(observed_at) AS observed_at
    FROM mart.renewal_management_contract_observation
    WHERE observed_at <= %s::timestamptz
    GROUP BY expiring_contract_id
), latest AS (
    SELECT o.observation_kind
    FROM latest_time AS lt
    INNER JOIN mart.renewal_management_contract_observation AS o
      ON o.expiring_contract_id = lt.expiring_contract_id
     AND o.observed_at = lt.observed_at
)
SELECT count(*) FILTER (WHERE observation_kind <> 'REMOVED')
FROM latest
"""

EQUALITY_QUERY = """
WITH distinct_on_value AS (
    SELECT count(*) FILTER (WHERE observation_kind <> 'REMOVED') AS value
    FROM (
        SELECT DISTINCT ON (expiring_contract_id) observation_kind
        FROM mart.renewal_management_contract_observation
        WHERE observed_at <= %s::timestamptz
        ORDER BY expiring_contract_id, observed_at DESC
    ) AS latest
), grouped_max_value AS (
    SELECT count(*) FILTER (WHERE o.observation_kind <> 'REMOVED') AS value
    FROM (
        SELECT expiring_contract_id, max(observed_at) AS observed_at
        FROM mart.renewal_management_contract_observation
        WHERE observed_at <= %s::timestamptz
        GROUP BY expiring_contract_id
    ) AS lt
    JOIN mart.renewal_management_contract_observation AS o
      ON o.expiring_contract_id = lt.expiring_contract_id
     AND o.observed_at = lt.observed_at
)
SELECT distinct_on_value.value, grouped_max_value.value,
       distinct_on_value.value = grouped_max_value.value AS equal_result
FROM distinct_on_value CROSS JOIN grouped_max_value
"""


def json_default(value: Any) -> Any:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(type(value).__name__)


def main() -> int:
    connection = connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart")
    try:
        with connection.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SELECT set_config('statement_timeout', '60000', true)")
            cursor.execute("SELECT clock_timestamp()")
            as_of = cursor.fetchone()[0]
            cursor.execute(EQUALITY_QUERY, (as_of, as_of))
            distinct_count, grouped_count, equal_result = cursor.fetchone()
            plans = {}
            for name, query in (("distinct_on", DISTINCT_ON_QUERY), ("grouped_max", GROUPED_MAX_QUERY)):
                cursor.execute(query, (as_of,))
                document = cursor.fetchone()[0][0]
                plan = document["Plan"]
                plans[name] = {
                    "execution_ms": document.get("Execution Time"),
                    "planning_ms": document.get("Planning Time"),
                    "rows": plan.get("Actual Rows"),
                    "node_type": plan.get("Node Type"),
                    "shared_hit_blocks": plan.get("Shared Hit Blocks"),
                    "shared_read_blocks": plan.get("Shared Read Blocks"),
                    "temp_read_blocks": plan.get("Temp Read Blocks"),
                    "temp_written_blocks": plan.get("Temp Written Blocks"),
                }
            cursor.execute("SELECT pg_total_relation_size(%s)", (TARGET,))
            relation_size_bytes = cursor.fetchone()[0]
            cursor.execute("ROLLBACK")
        print(json.dumps({
            "as_of": as_of,
            "distinct_on_count": distinct_count,
            "grouped_max_count": grouped_count,
            "equal_result": equal_result,
            "plans": plans,
            "relation_size_bytes": relation_size_bytes,
        }, ensure_ascii=False, default=json_default, indent=2))
        return 0
    finally:
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
