#!/usr/bin/env python3
"""Compare the current-M and reused-fact source extracts in one 1C snapshot."""

from __future__ import annotations

import os
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

try:
    from scripts.mart_connection import load_project_env
except ModuleNotFoundError:
    from mart_connection import load_project_env


load_project_env()


ROOT = Path(__file__).resolve().parents[1]
RGS_EXTRACT = ROOT / "sql/marts/revenue_group_summary_extract.sql"
DPFU_EXTRACTS = (
    ROOT / "sql/marts/dpfu_ancillary_revenue_extract_7575.sql",
    ROOT / "sql/marts/dpfu_ancillary_revenue_extract_7646.sql",
)
IP_EXTRACT = ROOT / "sql/marts/ip_revenue_daily_extract.sql"


def config() -> dict[str, str]:
    keys = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {key: os.environ.get("SOURCE_" + key) for key in keys}
    missing = ["SOURCE_" + key for key, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"],
        "dbname": values["PGDATABASE"], "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
    }
    if os.environ.get("SOURCE_PGSSLMODE"):
        result["sslmode"] = os.environ["SOURCE_PGSSLMODE"]
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date.fromordinal(today.toordinal() + 1)


def bind(sql: str, start: date, end: date) -> str:
    return (
        sql.replace("$1::date", f"DATE '{start.isoformat()}'")
        .replace("$2::date", f"DATE '{end.isoformat()}'")
        .strip()
        .rstrip(";")
    )


def current_m_sql(start: date, end: date) -> str:
    sql = RGS_EXTRACT.read_text(encoding="utf-8")
    return bind(sql[sql.index("WITH membership_base AS (") :], start, end)


def reused_dpfu_sql(start: date, end: date) -> str:
    branches = [bind(path.read_text(encoding="utf-8"), start, end) for path in DPFU_EXTRACTS]
    return f"""
        SELECT service_date AS revenue_date, club_id,
               '03.ДПФУ (ШТАТ)'::text AS revenue_article_code,
               sum(revenue_amount)::numeric(18, 2) AS revenue_amount
        FROM ({branches[0]} UNION ALL {branches[1]}) dpfu
        GROUP BY service_date, club_id
    """


def reused_ip_sql(start: date, end: date) -> str:
    sql = IP_EXTRACT.read_text(encoding="utf-8")
    sql = sql[sql.index("WITH qualified AS (") :]
    return f"""
        SELECT revenue_date, club_id,
               '04.ДПФУ (АРЕНДА ИП)'::text AS revenue_article_code,
               sum(revenue_amount)::numeric(18, 2) AS revenue_amount
        FROM ({bind(sql, start, end)}) ip
        WHERE club_id IS NOT NULL
        GROUP BY revenue_date, club_id
    """


def execute_comparison(cursor, current_sql: str, dpfu_sql: str, ip_sql: str) -> list[tuple]:
    cursor.execute(
        f"""
        WITH current_m AS (
            SELECT revenue_date, club_id, revenue_article_code,
                   sum(revenue_amount)::numeric(18, 2) AS revenue_amount
            FROM ({current_sql}) x
            WHERE revenue_article_code IN ('03.ДПФУ (ШТАТ)', '04.ДПФУ (АРЕНДА ИП)')
            GROUP BY 1, 2, 3
        ), reused AS (
            SELECT * FROM ({dpfu_sql}) dpfu
            UNION ALL
            SELECT * FROM ({ip_sql}) ip
        ), difference AS (
            SELECT coalesce(c.revenue_article_code, r.revenue_article_code) AS article,
                   c.revenue_amount AS current_m_amount,
                   r.revenue_amount AS reused_amount
            FROM current_m c
            FULL OUTER JOIN reused r
              ON r.revenue_date = c.revenue_date
             AND r.club_id = c.club_id
             AND r.revenue_article_code = c.revenue_article_code
        )
        SELECT article,
               count(*) FILTER (WHERE current_m_amount IS NOT NULL) AS current_m_keys,
               coalesce(sum(current_m_amount), 0)::numeric(18, 2) AS current_m_sum,
               count(*) FILTER (WHERE reused_amount IS NOT NULL) AS reused_keys,
               coalesce(sum(reused_amount), 0)::numeric(18, 2) AS reused_sum,
               count(*) FILTER (WHERE current_m_amount IS DISTINCT FROM reused_amount) AS differing_keys
        FROM difference
        GROUP BY article
        ORDER BY article
        """
    )
    return cursor.fetchall()


def main() -> None:
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    with psycopg.connect(**config()) as source:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            rows = execute_comparison(
                cursor,
                current_m_sql(start, end),
                reused_dpfu_sql(start, end),
                reused_ip_sql(start, end),
            )
            print(f"SOURCE_REUSE_SNAPSHOT horizon={start}..{end}", flush=True)
            for row in rows:
                print(
                    "SOURCE_REUSE_CONTROL "
                    f"article={row[0]} current_m_keys={row[1]} current_m_sum={row[2]} "
                    f"reused_keys={row[3]} reused_sum={row[4]} differing_keys={row[5]}",
                    flush=True,
                )
            source.rollback()


if __name__ == "__main__":
    main()
