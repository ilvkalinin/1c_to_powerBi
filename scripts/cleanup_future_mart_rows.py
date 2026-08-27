#!/usr/bin/env python3
"""Atomically remove fact rows dated after today's Moscow calendar date."""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
from psycopg import sql


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry, load_project_env


# Only materialized facts whose column is the date/timestamp of the fact itself.
# Views and descriptive dates (for example contract end or activation attributes)
# are deliberately absent: they may be future while the fact row is valid today.
FACT_DATE_COLUMNS = (
    ("administrator_card_gymmy_daily", "event_date"),
    ("ancillary_revenue_movement", "service_date"),
    ("client_base_daily", "report_date"),
    ("client_base_snapshot", "report_date"),
    ("client_base_retention", "report_date"),
    ("club_attendance_hourly", "visit_date"),
    ("club_day_metrics", "event_date"),
    ("crm_interaction", "report_date"),
    ("crm_interaction_phone", "phone_at"),
    ("dpfu_plan_assignment", "plan_date"),
    ("feedback_interaction", "created_at"),
    ("fitness_leads_funnel_task", "task_date"),
    ("fitness_leads_funnel_task_service", "service_date"),
    ("group_lesson", "lesson_start_at"),
    ("guest_visit_conversion", "guest_visit_date"),
    ("ip_revenue_daily", "revenue_date"),
    ("ip_training_daily", "training_date"),
    ("lesson_room_slot_5m", "slot_start_at"),
    ("marketing_funnel_task", "task_date"),
    ("membership_contract_kpi_unit", "metric_date"),
    ("membership_receipt_movement", "receipt_date"),
    ("new_first_visit", "first_visit_date"),
    ("newcomer_engagement_milestone", "checkpoint_date"),
    ("newcomer_engagement_second_month", "month_of_engagement"),
    ("prebooking_state_event", "state_event_at"),
    ("preparation_renewal_checkpoint", "checkpoint_date"),
    ("revenue_group_summary_daily", "revenue_date"),
    ("visit_client_day", "visit_date"),
    ("visit_client_day__loading", "visit_date"),
)


load_project_env()


def mart_config(application_name: str) -> dict[str, object]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get("MART_" + name) for name in names}
    missing = ["MART_" + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result: dict[str, object] = {
        "host": values["PGHOST"],
        "port": values["PGPORT"],
        "dbname": values["PGDATABASE"],
        "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
        "application_name": application_name,
        "connect_timeout": 15,
        "keepalives": 1,
        "keepalives_idle": 60,
        "keepalives_interval": 15,
        "keepalives_count": 4,
        "tcp_user_timeout": 180_000,
    }
    if sslmode := os.environ.get("MART_PGSSLMODE"):
        result["sslmode"] = sslmode
    return result


def future_count(cursor, relation: str, column: str, as_of) -> int:
    query = sql.SQL("SELECT count(*)::bigint FROM {} WHERE {} > %s").format(
        sql.Identifier("mart", relation), sql.Identifier(column)
    )
    cursor.execute(query, (as_of,))
    return cursor.fetchone()[0]


def delete_future(cursor, relation: str, column: str, as_of) -> int:
    query = sql.SQL("DELETE FROM {} WHERE {} > %s").format(
        sql.Identifier("mart", relation), sql.Identifier(column)
    )
    cursor.execute(query, (as_of,))
    return cursor.rowcount


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="commit the reviewed cleanup")
    args = parser.parse_args()
    as_of = datetime.now(ZoneInfo("Europe/Moscow")).date()
    target = connect_with_retry(
        lambda: psycopg.connect(**mart_config("mart_future_fact_cleanup")),
        endpoint="mart",
    )
    try:
        with target.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ")
            cursor.execute("SET LOCAL lock_timeout = '60s'")
            cursor.execute("SET LOCAL statement_timeout = '180s'")
            before = {
                (relation, column): future_count(cursor, relation, column, as_of)
                for relation, column in FACT_DATE_COLUMNS
            }
            print(f"FUTURE_FACT_CLEANUP_PRECHECK as_of={as_of} values={before}", flush=True)
            if not args.apply:
                target.rollback()
                print("FUTURE_FACT_CLEANUP_DRY_RUN_PASS", flush=True)
                return
            deleted = {
                (relation, column): delete_future(cursor, relation, column, as_of)
                for relation, column in FACT_DATE_COLUMNS
            }
            if deleted != before:
                raise RuntimeError(f"Deleted rows differ from precheck: before={before}; deleted={deleted}")
            after = {
                (relation, column): future_count(cursor, relation, column, as_of)
                for relation, column in FACT_DATE_COLUMNS
            }
            if any(after.values()):
                raise RuntimeError(f"Future rows remain after cleanup: {after}")
            target.commit()
            print(
                f"FUTURE_FACT_CLEANUP_COMMIT as_of={as_of} "
                f"deleted={deleted} postcheck={after}",
                flush=True,
            )
    except Exception:
        try:
            target.rollback()
        finally:
            target.close()
        raise
    else:
        target.close()


if __name__ == "__main__":
    main()
