#!/usr/bin/env python3
"""Atomically rebuild mart.revenue_group_summary_daily for one BR-003 horizon."""

from __future__ import annotations

import argparse
import os
import time
import sys
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
EXTRACT = ROOT / "sql/marts/revenue_group_summary_extract.sql"
TARGET_COLUMNS = "revenue_date, club_id, revenue_article_code, revenue_amount"
SOURCE_COLUMNS = "source_branch, revenue_date, club_id, revenue_article_code, revenue_amount"
SOURCE_ONLY_ARTICLES = ("02.ЧЛЕНСТВО", "06.ДРЦ")
REUSED_ARTICLES = (
    "03.ДПФУ (ШТАТ)",
    "04.ДПФУ (АРЕНДА ИП)",
    "05.РЕЦЕПЦИЯ",
)


def config(prefix: str) -> dict[str, str]:
    keys = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {key: os.environ.get(prefix + key) for key in keys}
    missing = [prefix + key for key, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"],
        "port": values["PGPORT"],
        "dbname": values["PGDATABASE"],
        "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
    }
    if prefix == "SOURCE_" and os.environ.get("SOURCE_PGSSLMODE"):
        result["sslmode"] = os.environ["SOURCE_PGSSLMODE"]
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date.fromordinal(today.toordinal() + 1)


def direct_source_extract(start: date, end: date) -> str:
    """Return only the still-source-owned BR-003 branches (02 and 06).

    The complete historical extract also contains 03--05.  These are now
    supplied by common mart facts, so an outer filter is not sufficient: it
    may still execute the expensive reused CTEs.  Keep the unchanged
    membership CTEs and cut the source SQL before the first reused branch.
    """
    sql = EXTRACT.read_text(encoding="utf-8")
    sql = sql[sql.index("WITH membership_base AS (") :].strip().rstrip(";")
    reused_branch_start = "\ndpfu_7575 AS ("
    if reused_branch_start not in sql:
        raise RuntimeError("Cannot isolate direct BR-003 source branches")
    membership_ctes = sql[: sql.index(reused_branch_start)].rstrip().rstrip(",")
    return (
        f"""{membership_ctes},
source_branches AS (
    SELECT * FROM membership_contract
    UNION ALL SELECT * FROM membership_other
    UNION ALL SELECT * FROM membership_goods
)
SELECT source_branch, revenue_date, club_id, revenue_article_code, revenue_amount
FROM source_branches
WHERE club_id IS NOT NULL
  AND revenue_article_code = ANY(ARRAY['02.ЧЛЕНСТВО', '06.ДРЦ'])"""
        .replace("$1::date", f"DATE '{start.isoformat()}'")
        .replace("$2::date", f"DATE '{end.isoformat()}'")
    )


def controls(cursor, relation: str, branch_column: str) -> dict[str, tuple[int, object]]:
    cursor.execute(
        f"""
        SELECT {branch_column}, count(*)::bigint,
               coalesce(sum(revenue_amount), 0)::numeric(18, 2)
        FROM {relation}
        GROUP BY {branch_column}
        ORDER BY {branch_column}
        """
    )
    return {key: (rows, amount) for key, rows, amount in cursor}


def require_stage_integrity(cursor) -> None:
    cursor.execute(
        """
        SELECT count(*) FROM (
            SELECT 1
            FROM _revenue_group_summary_stage
            GROUP BY revenue_date, club_id, revenue_article_code
            HAVING count(*) > 1
        ) duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Duplicate logical key in revenue-group-summary stage")
    cursor.execute(
        """
        SELECT count(*)
        FROM _revenue_group_summary_stage
        WHERE revenue_date IS NULL OR club_id IS NULL OR revenue_article_code IS NULL
           OR revenue_amount IS NULL
           OR revenue_article_code NOT IN (
               '02.ЧЛЕНСТВО', '03.ДПФУ (ШТАТ)', '04.ДПФУ (АРЕНДА ИП)',
               '05.РЕЦЕПЦИЯ', '06.ДРЦ'
           )
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Fact-contract violation in revenue-group-summary stage")


def require_source_equivalence(cursor) -> None:
    cursor.execute(
        """
        WITH source_daily AS (
            SELECT revenue_date, club_id, revenue_article_code,
                   sum(revenue_amount)::numeric(18, 2) AS revenue_amount
            FROM _revenue_group_summary_source_stage
            GROUP BY 1, 2, 3
        ), difference AS (
            SELECT coalesce(s.revenue_date, t.revenue_date) AS revenue_date,
                   coalesce(s.club_id, t.club_id) AS club_id,
                   coalesce(s.revenue_article_code, t.revenue_article_code) AS revenue_article_code,
                   s.revenue_amount AS source_amount,
                   t.revenue_amount AS stage_amount
            FROM source_daily s
            FULL OUTER JOIN (
                SELECT revenue_date, club_id, revenue_article_code, revenue_amount
                FROM _revenue_group_summary_stage
                WHERE revenue_article_code IN ('02.ЧЛЕНСТВО', '06.ДРЦ')
            ) t
              ON t.revenue_date = s.revenue_date
             AND t.club_id = s.club_id
             AND t.revenue_article_code = s.revenue_article_code
        )
        SELECT count(*)
        FROM difference
        WHERE source_amount IS DISTINCT FROM stage_amount
        """
    )
    differences = cursor.fetchone()[0]
    if differences:
        raise RuntimeError(f"{differences} stage keys differ from independent source snapshot")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform approved target DML")
    args = parser.parse_args()
    if not args.apply:
        raise SystemExit("Refusing target DML without --apply")

    started_at = time.monotonic()
    horizon_start, horizon_end = br003_horizon(
        datetime.now(ZoneInfo("Europe/Moscow")).date()
    )
    source_extract = direct_source_extract(horizon_start, horizon_end)
    print(f"LOAD_STARTED horizon={horizon_start}..{horizon_end}", flush=True)

    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        with source.cursor() as source_cur, target.cursor() as target_cur:
            source_cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            source_started_at = time.monotonic()

            target_cur.execute("BEGIN")
            target_cur.execute(
                "SELECT pg_advisory_xact_lock(hashtext(%s))",
                ("mart.revenue_group_summary_daily:refresh",),
            )
            target_cur.execute(
                """
                CREATE TEMP TABLE _revenue_group_summary_source_stage (
                    source_branch text NOT NULL,
                    revenue_date date NOT NULL,
                    club_id text NOT NULL,
                    revenue_article_code text NOT NULL,
                    revenue_amount numeric(18, 2) NOT NULL
                ) ON COMMIT DROP
                """
            )
            target_cur.execute(
                """
                CREATE TEMP TABLE _revenue_group_summary_stage (
                    LIKE mart.revenue_group_summary_daily INCLUDING DEFAULTS
                ) ON COMMIT DROP
                """
            )
            target_cur.execute(
                """
                CREATE TEMP TABLE _revenue_group_summary_reused_stage (
                    revenue_date date NOT NULL,
                    club_id text NOT NULL,
                    revenue_article_code text NOT NULL,
                    revenue_amount numeric(18, 2) NOT NULL
                ) ON COMMIT DROP
                """
            )

            stream_started_at = time.monotonic()
            with target_cur.copy(
                f"COPY _revenue_group_summary_source_stage ({SOURCE_COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
            ) as target_copy, source_cur.copy(
                f"COPY ({source_extract}) TO STDOUT WITH (FORMAT BINARY)"
            ) as source_copy:
                for block in source_copy:
                    target_copy.write(block)
            print(
                f"SOURCE_COPY seconds={time.monotonic() - stream_started_at:.2f}",
                flush=True,
            )

            source_controls = controls(
                target_cur, "_revenue_group_summary_source_stage", "source_branch"
            )
            if not source_controls:
                raise RuntimeError("Unexpected empty source extract")
            print(
                f"SOURCE_SNAPSHOT seconds={time.monotonic() - source_started_at:.2f}",
                flush=True,
            )
            for branch, (rows, amount) in source_controls.items():
                print(f"SOURCE_CONTROL branch={branch} rows={rows} revenue_amount={amount}", flush=True)

            target_cur.execute(
                """
                INSERT INTO _revenue_group_summary_reused_stage
                    (revenue_date, club_id, revenue_article_code, revenue_amount)
                SELECT service_date, club_id, '03.ДПФУ (ШТАТ)',
                       sum(revenue_amount)::numeric(18, 2)
                FROM mart.ancillary_revenue_movement
                WHERE revenue_scope = 'dpfu'
                  AND service_date >= %s AND service_date < %s
                  AND club_id IS NOT NULL
                GROUP BY service_date, club_id
                UNION ALL
                SELECT revenue_date, club_id, '04.ДПФУ (АРЕНДА ИП)',
                       sum(revenue_amount)::numeric(18, 2)
                FROM mart.ip_revenue_daily
                WHERE revenue_date >= %s AND revenue_date < %s
                  AND club_id IS NOT NULL
                GROUP BY revenue_date, club_id
                UNION ALL
                SELECT service_date, club_id, '05.РЕЦЕПЦИЯ',
                       sum(revenue_amount)::numeric(18, 2)
                FROM mart.ancillary_revenue_movement
                WHERE revenue_scope = 'reception'
                  AND service_date >= %s AND service_date < %s
                  AND club_id IS NOT NULL
                GROUP BY service_date, club_id
                """,
                (
                    horizon_start,
                    horizon_end,
                    horizon_start,
                    horizon_end,
                    horizon_start,
                    horizon_end,
                ),
            )
            reused_controls = controls(
                target_cur,
                "_revenue_group_summary_reused_stage",
                "revenue_article_code",
            )
            if set(reused_controls) != set(REUSED_ARTICLES):
                raise RuntimeError("Expected both reused revenue articles in the stage")
            target_cur.execute(
                """
                INSERT INTO _revenue_group_summary_stage
                    (revenue_date, club_id, revenue_article_code, revenue_amount)
                SELECT revenue_date, club_id, revenue_article_code,
                       sum(revenue_amount)::numeric(18, 2)
                FROM (
                    SELECT revenue_date, club_id, revenue_article_code, revenue_amount
                    FROM _revenue_group_summary_source_stage
                    WHERE revenue_article_code = ANY(%s)
                    UNION ALL
                    SELECT revenue_date, club_id, revenue_article_code, revenue_amount
                    FROM _revenue_group_summary_reused_stage
                ) all_rows
                GROUP BY revenue_date, club_id, revenue_article_code
                """,
                (list(SOURCE_ONLY_ARTICLES),),
            )
            require_stage_integrity(target_cur)
            require_source_equivalence(target_cur)
            stage_controls = controls(
                target_cur, "_revenue_group_summary_stage", "revenue_article_code"
            )
            print("STAGE_PASS duplicate_keys=0 contract_violations=0 source_key_differences=0", flush=True)
            for article, (rows, amount) in stage_controls.items():
                print(f"STAGE_CONTROL article={article} rows={rows} revenue_amount={amount}", flush=True)
            for article, (rows, amount) in reused_controls.items():
                print(f"REUSED_CONTROL article={article} rows={rows} revenue_amount={amount}", flush=True)

            target_cur.execute("DELETE FROM mart.revenue_group_summary_daily")
            target_cur.execute(
                f"""
                INSERT INTO mart.revenue_group_summary_daily ({TARGET_COLUMNS})
                SELECT {TARGET_COLUMNS}
                FROM _revenue_group_summary_stage
                """
            )
            persisted_controls = controls(
                target_cur, "mart.revenue_group_summary_daily", "revenue_article_code"
            )
            if persisted_controls != stage_controls:
                raise RuntimeError("Persistent fact controls differ from staged controls")
            target.commit()
            source.rollback()
            print(
                f"DML_COMMITTED seconds={time.monotonic() - started_at:.2f} "
                f"rows={sum(rows for rows, _ in persisted_controls.values())}",
                flush=True,
            )
            for article, (rows, amount) in persisted_controls.items():
                print(f"TARGET_CONTROL article={article} rows={rows} revenue_amount={amount}", flush=True)


if __name__ == "__main__":
    main()
