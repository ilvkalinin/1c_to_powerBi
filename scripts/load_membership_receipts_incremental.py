#!/usr/bin/env python3
"""Synchronise membership receipt facts without invoking the full rebuild."""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.load_membership_receipts import (
    ALL_STAGE_COLUMNS,
    HISTORY_EXTRACT,
    KPI_COLUMNS,
    MOVEMENT_COLUMNS,
    br003_horizon,
    config,
    copy_contract_attributes,
    kpi_controls,
    movement_controls,
    require_stage_integrity,
    source_all_projection,
    source_history_projection,
)
from scripts.mart_connection import connect_with_retry

CONFIG = ROOT / "config/membership_receipts_incremental.json"
TARGETS = {
    "movement": "mart.membership_receipt_movement",
    "kpi": "mart.membership_contract_kpi_unit",
}
STAGES = {
    "movement": "_membership_receipt_movement_stage",
    "kpi": "_membership_contract_kpi_unit_stage",
}
ORDER = ("movement", "kpi")


def columns(value: str) -> tuple[str, ...]:
    return tuple(column.strip() for column in value.split(","))


def load_config(path: Path) -> None:
    actual = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "objects": [TARGETS[name] for name in ORDER],
        "mode": "composite_target_row_diff",
        "timezone": "Europe/Moscow",
        "change_detection": "source_snapshot_to_target_exact_row_multiset_diff",
        "deletion_policy": "delete_target_rows_absent_or_different_in_source_snapshot",
        "no_change_policy": "no_final_target_dml",
    }
    if any(actual.get(key) != value for key, value in expected.items()):
        raise RuntimeError("Unexpected membership incremental configuration")
    if actual.get("watermark") is not None or actual.get("incremental_sla") is not None:
        raise RuntimeError("Membership incremental runner must not claim watermark or SLA")


def equality(left: str, right: str, names: tuple[str, ...]) -> str:
    return " AND ".join(
        f"{left}.{name} IS NOT DISTINCT FROM {right}.{name}" for name in names
    )


def exact_delta(cursor, name: str, names: tuple[str, ...]) -> int:
    selected = ", ".join(names)
    cursor.execute(
        f"""
        SELECT count(*) FROM (
          (SELECT {selected} FROM {STAGES[name]}
           EXCEPT ALL
           SELECT {selected} FROM {TARGETS[name]})
          UNION ALL
          (SELECT {selected} FROM {TARGETS[name]}
           EXCEPT ALL
           SELECT {selected} FROM {STAGES[name]})
        ) AS exact_difference
        """
    )
    return cursor.fetchone()[0]


def sync_relation(cursor, name: str, names: tuple[str, ...]) -> None:
    selected = ", ".join(names)
    stage_selected = ", ".join(f"stage.{column}" for column in names)
    match = equality("target", "stage", names)
    cursor.execute(
        f"""
        DELETE FROM {TARGETS[name]} AS target
        WHERE NOT EXISTS (
          SELECT 1 FROM {STAGES[name]} AS stage WHERE {match}
        )
        """
    )
    cursor.execute(
        f"""
        INSERT INTO {TARGETS[name]} ({selected})
        SELECT {stage_selected}
        FROM {STAGES[name]} AS stage
        WHERE NOT EXISTS (
          SELECT 1 FROM {TARGETS[name]} AS target WHERE {match}
        )
        """
    )


def create_stages(cursor) -> None:
    cursor.execute(
        """CREATE TEMP TABLE _membership_source_stage (
          row_type text NOT NULL, source_kind text, source_object text, kpi_unit_key text, kpi_unit_kind text, metric_date date,
          receipt_date date, source_group_recorder_id text, source_group_line_no integer, contract_id text, client_key text,
          analytics_text text, payment_period integer, payment_type text, movement_kind smallint, recorder_type text,
          movement_club_id text, access_club_id text, sales_point_club_id text, reporting_club_id text, manager_id text,
          product_id text, source_product_name text, source_product_freeze_days numeric, contract_activation_date date,
          contract_start_date date, contract_end_date date, contract_term_days numeric, source_stage_id text, source_stage text,
          super_stage text, payment_source text, product_age_category text, purchase_type text, purchase_type_id text,
          membership_kind text, membership_kind_id text, club_access_type text, club_access_type_id text, access_time_type text,
          access_zone text, amount_raw numeric, amount_signed numeric, co_access_amount numeric, receipt_amount_net numeric,
          service_group text, source_movement_count bigint, free_freeze_before_activation_days numeric,
          effective_duration_days numeric, list_contract_price numeric, calculation_price numeric, calculation_mode text
        ) ON COMMIT DROP"""
    )
    cursor.execute(
        """CREATE TEMP TABLE _membership_contract_history_stage (
          contract_id text PRIMARY KEY, client_key text NOT NULL, activation_date date,
          start_date date, end_date date, payment_type text NOT NULL
        ) ON COMMIT DROP"""
    )
    for name in ORDER:
        cursor.execute(
            f"CREATE TEMP TABLE {STAGES[name]} "
            f"(LIKE {TARGETS[name]} INCLUDING DEFAULTS) ON COMMIT DROP"
        )


def derive_stages(source_cursor, target_cursor, start, end) -> tuple[tuple[object, ...], tuple[object, ...]]:
    all_query = source_all_projection(start, end)
    history_query = source_history_projection(start, end)
    with target_cursor.copy(
        f"COPY _membership_source_stage ({ALL_STAGE_COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
    ) as target_copy, source_cursor.copy(
        f"COPY ({all_query}) TO STDOUT WITH (FORMAT BINARY)"
    ) as source_copy:
        for block in source_copy:
            target_copy.write(block)
    with target_cursor.copy(
        "COPY _membership_contract_history_stage "
        "(contract_id, client_key, activation_date, start_date, end_date, payment_type) "
        "FROM STDIN WITH (FORMAT BINARY)"
    ) as target_copy, source_cursor.copy(
        f"COPY ({history_query}) TO STDOUT WITH (FORMAT BINARY)"
    ) as source_copy:
        for block in source_copy:
            target_copy.write(block)
    target_cursor.execute(
        """
        WITH history_starts AS (
          SELECT client_key, start_date, min(contract_id) AS contract_id
          FROM _membership_contract_history_stage
          WHERE start_date IS NOT NULL AND end_date >= start_date GROUP BY 1, 2
        ), predecessor AS (
          SELECT client_key, start_date,
                 lag(contract_id) OVER (PARTITION BY client_key ORDER BY start_date) AS previous_contract_id
          FROM history_starts
        ), predecessor_attr AS (
          SELECT p.client_key, p.start_date, h.end_date AS previous_end_date,
                 h.payment_type AS previous_payment_type
          FROM predecessor p LEFT JOIN _membership_contract_history_stage h
            ON h.contract_id = p.previous_contract_id
        )
        UPDATE _membership_source_stage s
        SET super_stage = CASE
          WHEN pa.previous_end_date IS NOT NULL AND s.contract_activation_date IS NOT NULL
               AND date_trunc('month', pa.previous_end_date) = date_trunc('month', s.contract_activation_date)
               AND pa.previous_payment_type = 'Рекарринг' THEN coalesce(s.source_stage, 'NEW')
          WHEN pa.previous_end_date IS NOT NULL AND s.contract_activation_date IS NOT NULL
               AND date_trunc('month', s.contract_activation_date)-date_trunc('month', pa.previous_end_date)>interval '0 months'
               AND s.source_stage = 'RENEW' THEN 'RENEW(БП)'
          WHEN pa.previous_end_date IS NOT NULL AND s.contract_activation_date IS NOT NULL
               AND s.contract_activation_date-pa.previous_end_date < -180 AND s.source_stage = 'EX' THEN 'NEW'
          WHEN s.source_stage IS NULL OR s.source_stage = 'NEW' THEN 'NEW'
          ELSE s.source_stage END
        FROM predecessor_attr pa
        WHERE s.payment_type = 'Предоплата' AND s.client_key = pa.client_key
          AND s.contract_start_date = pa.start_date
        """
    )
    target_cursor.execute(
        """SELECT DISTINCT contract_id FROM _membership_source_stage
           WHERE row_type = 'movement' AND payment_type IN ('Предоплата', 'Рекарринг')
             AND contract_id IS NOT NULL ORDER BY 1"""
    )
    copy_contract_attributes(source_cursor, target_cursor, [row[0] for row in target_cursor.fetchall()], start, end)
    target_cursor.execute(
        f"""INSERT INTO {STAGES['movement']} ({MOVEMENT_COLUMNS})
        SELECT source_kind, source_object, receipt_date, source_group_recorder_id, source_group_line_no,
               contract_id, client_key, analytics_text, payment_period, payment_type, movement_kind, recorder_type,
               movement_club_id, access_club_id, sales_point_club_id, reporting_club_id, manager_id, product_id,
               source_product_name, source_product_freeze_days, contract_activation_date, contract_start_date,
               contract_end_date, contract_term_days, source_stage_id, source_stage, super_stage, payment_source,
               product_age_category, purchase_type, purchase_type_id, membership_kind, membership_kind_id,
               club_access_type, club_access_type_id, access_time_type, access_zone, amount_raw, amount_signed,
               co_access_amount, receipt_amount_net, service_group, source_movement_count
        FROM _membership_source_stage WHERE row_type = 'movement'"""
    )
    target_cursor.execute(
        f"""INSERT INTO {STAGES['kpi']} ({KPI_COLUMNS})
        WITH kpi_groups AS (
          SELECT CASE WHEN payment_type='Рекарринг' THEN contract_id||':'||payment_period::text ELSE contract_id END AS kpi_unit_key,
                 CASE WHEN payment_type='Рекарринг' THEN 'recurring_payment' ELSE 'prepayment_contract' END AS kpi_unit_kind,
                 CASE WHEN payment_type='Рекарринг' THEN min(receipt_date) ELSE min(contract_activation_date) END AS metric_date,
                 contract_id, min(client_key) AS client_key, CASE WHEN payment_type='Рекарринг' THEN payment_period END AS payment_period,
                 min(access_club_id) AS access_club_id, min(sales_point_club_id) AS sales_point_club_id, min(manager_id) AS manager_id,
                 min(product_id) AS product_id, min(contract_activation_date) AS contract_activation_date,
                 min(contract_start_date) AS contract_start_date, min(contract_end_date) AS contract_end_date,
                 min(contract_term_days) AS contract_term_days, min(source_stage) AS source_stage, min(super_stage) AS super_stage,
                 payment_type, min(payment_source) AS payment_source, min(product_age_category) AS product_age_category,
                 min(purchase_type) AS purchase_type, min(membership_kind) AS membership_kind,
                 min(club_access_type) AS club_access_type, min(access_time_type) AS access_time_type,
                 min(access_zone) AS access_zone, min(calculation_mode) AS calculation_mode,
                 sum(receipt_amount_net)::numeric AS net_receipt_amount, sum(source_movement_count)::bigint AS source_movement_count
          FROM _membership_source_stage WHERE row_type='movement' AND payment_type IN ('Предоплата','Рекарринг')
          GROUP BY payment_type, contract_id, payment_period
        )
        SELECT kg.kpi_unit_key, kg.kpi_unit_kind, kg.metric_date, kg.contract_id, kg.client_key, kg.payment_period,
               kg.access_club_id, kg.sales_point_club_id, kg.manager_id, kg.product_id, kg.contract_activation_date,
               kg.contract_start_date, kg.contract_end_date, kg.contract_term_days,
               coalesce(f.free_freeze_before_activation_days,0)::numeric,
               CASE WHEN kg.payment_type='Рекарринг' THEN 30.42::numeric
                    ELSE kg.contract_term_days+coalesce(f.free_freeze_before_activation_days,0) END,
               kg.source_stage, kg.super_stage, kg.payment_type, kg.payment_source, kg.product_age_category,
               kg.purchase_type, kg.membership_kind, kg.club_access_type, kg.access_time_type, kg.access_zone,
               p.list_contract_price,
               CASE WHEN kg.super_stage IN ('Продажа','Списание') OR kg.calculation_mode='Ф' THEN kg.net_receipt_amount
                    WHEN kg.calculation_mode='П' THEN p.list_contract_price ELSE NULL END,
               kg.calculation_mode, kg.source_movement_count
        FROM kpi_groups kg LEFT JOIN _membership_price_stage p USING(contract_id)
        LEFT JOIN _membership_freeze_stage f USING(contract_id)
        WHERE kg.net_receipt_amount <> 0 AND kg.contract_end_date-kg.contract_start_date > 28"""
    )
    require_stage_integrity(target_cursor)
    return movement_controls(target_cursor, STAGES["movement"]), kpi_controls(target_cursor, STAGES["kpi"])


def run(start, end) -> None:
    started = time.monotonic()
    relation_columns = {"movement": columns(MOVEMENT_COLUMNS), "kpi": columns(KPI_COLUMNS)}
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        try:
            with source.cursor() as source_cursor, target.cursor() as target_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                target_cursor.execute("BEGIN")
                target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.membership_receipts:incremental",))
                for name in ORDER:
                    target_cursor.execute("SELECT to_regclass(%s)", (TARGETS[name],))
                    if target_cursor.fetchone()[0] is None:
                        raise RuntimeError("Incremental refresh requires existing targets")
                create_stages(target_cursor)
                staged_controls = derive_stages(source_cursor, target_cursor, start, end)
                if not all(control[0] for control in staged_controls):
                    raise RuntimeError("Unexpected empty membership source stage")
                before = {name: exact_delta(target_cursor, name, relation_columns[name]) for name in ORDER}
                if not any(before.values()):
                    target.commit()
                    source.rollback()
                    print(f"NO_CHANGES elapsed_seconds={time.monotonic() - started:.3f}", flush=True)
                    return
                for name in ORDER:
                    sync_relation(target_cursor, name, relation_columns[name])
                if any(exact_delta(target_cursor, name, relation_columns[name]) for name in ORDER):
                    raise RuntimeError("Pre-commit exact mismatch")
                persisted = (
                    movement_controls(target_cursor, TARGETS["movement"]),
                    kpi_controls(target_cursor, TARGETS["kpi"]),
                )
                if persisted != staged_controls:
                    raise RuntimeError("Persisted controls differ from the staged source snapshot")
                target.commit()
                source.rollback()
                print(f"TARGET_COMMIT delta_before={before} elapsed_seconds={time.monotonic() - started:.3f}", flush=True)
        except Exception:
            target.rollback()
            raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=CONFIG)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan-only", action="store_true")
    mode.add_argument("--run", action="store_true", help="perform approved target DML")
    args = parser.parse_args()
    load_config(args.config)
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    if args.plan_only:
        print(f"PLAN_OK mode=composite_target_row_diff horizon={start}..{end}", flush=True)
        return
    run(start, end)


if __name__ == "__main__":
    main()
