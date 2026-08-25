#!/usr/bin/env python3
"""Atomically rebuild the shared membership receipt and KPI marts."""

from __future__ import annotations

import argparse
import os
import sys
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
EXTRACT = ROOT / "sql/marts/membership_receipts_extract.sql"
HISTORY_EXTRACT = ROOT / "sql/marts/membership_contract_history_extract.sql"

MOVEMENT_COLUMNS = """
source_kind, source_object, receipt_date, source_group_recorder_id,
source_group_line_no, contract_id, client_key, accounting_analytics_text,
payment_period, payment_type, movement_kind, recorder_type, movement_club_id,
access_club_id, sales_point_club_id, reporting_club_id, manager_id, product_id,
source_product_name, source_product_freeze_days, contract_activation_date,
contract_start_date, contract_end_date, contract_term_days, source_stage_id,
source_stage, super_stage, payment_source, product_age_category, purchase_type,
purchase_type_id, membership_kind, membership_kind_id, club_access_type,
club_access_type_id, access_time_type, access_zone, amount_raw, amount_signed,
co_access_amount, receipt_amount_net, service_group, source_movement_count
""".replace("\n", " ")

KPI_COLUMNS = """
kpi_unit_key, kpi_unit_kind, metric_date, contract_id, client_key,
payment_period, access_club_id, sales_point_club_id, manager_id, product_id,
contract_activation_date, contract_start_date, contract_end_date,
contract_term_days, free_freeze_before_activation_days, effective_duration_days,
source_stage, super_stage, payment_type, payment_source, product_age_category,
purchase_type, membership_kind, club_access_type, access_time_type, access_zone,
list_contract_price, calculation_price, calculation_mode, source_movement_count
""".replace("\n", " ")

MOVEMENT_SOURCE_COLUMNS = MOVEMENT_COLUMNS.replace(
    "accounting_analytics_text", "analytics_text AS accounting_analytics_text"
)

ALL_STAGE_COLUMNS = """
row_type, source_kind, source_object, kpi_unit_key, kpi_unit_kind, metric_date,
receipt_date, source_group_recorder_id, source_group_line_no, contract_id,
client_key, analytics_text, payment_period, payment_type, movement_kind,
recorder_type, movement_club_id, access_club_id, sales_point_club_id,
reporting_club_id, manager_id, product_id, source_product_name,
source_product_freeze_days, contract_activation_date, contract_start_date,
contract_end_date, contract_term_days, source_stage_id, source_stage,
super_stage, payment_source, product_age_category, purchase_type,
purchase_type_id, membership_kind, membership_kind_id, club_access_type,
club_access_type_id, access_time_type, access_zone, amount_raw, amount_signed,
co_access_amount, receipt_amount_net, service_group, source_movement_count,
free_freeze_before_activation_days, effective_duration_days, list_contract_price,
calculation_price, calculation_mode
""".replace("\n", " ")


def config(prefix: str) -> dict[str, str]:
    keys = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {key: os.environ.get(prefix + key) for key in keys}
    missing = [prefix + key for key, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"],
        "dbname": values["PGDATABASE"], "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
    }
    if prefix == "SOURCE_" and os.environ.get("SOURCE_PGSSLMODE"):
        result["sslmode"] = os.environ["SOURCE_PGSSLMODE"]
    return result


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date(today.year + 1, 1, 1)


def source_projection(start: date, end: date, row_type: str, columns: str) -> str:
    base = EXTRACT.read_text(encoding="utf-8").strip().rstrip(";")
    base = base.replace("$1::date", f"DATE '{start.isoformat()}'")
    base = base.replace("$2::date", f"DATE '{end.isoformat()}'")
    return f"SELECT {columns} FROM ({base}) membership_source WHERE row_type = '{row_type}'"


def source_all_projection(start: date, end: date) -> str:
    return EXTRACT.read_text(encoding="utf-8").strip().rstrip(";").replace(
        "$1::date", f"DATE '{start.isoformat()}'"
    ).replace("$2::date", f"DATE '{end.isoformat()}'")


def source_history_projection(start: date, end: date) -> str:
    return HISTORY_EXTRACT.read_text(encoding="utf-8").strip().rstrip(";").replace(
        "$1::date", f"DATE '{start.isoformat()}'"
    ).replace("$2::date", f"DATE '{end.isoformat()}'")


def movement_controls(cursor, relation: str) -> tuple[object, ...]:
    cursor.execute(
        f"""
        SELECT count(*)::bigint, coalesce(sum(receipt_amount_net), 0)::numeric,
               count(*) FILTER (WHERE reporting_club_id IS NULL)::bigint,
               count(*) FILTER (WHERE source_movement_count <= 0)::bigint
        FROM {relation}
        """
    )
    return cursor.fetchone()


def kpi_controls(cursor, relation: str) -> tuple[object, ...]:
    cursor.execute(
        f"""
        SELECT count(*)::bigint, coalesce(sum(calculation_price), 0)::numeric,
               count(*) FILTER (WHERE metric_date IS NULL)::bigint,
               count(*) FILTER (WHERE source_movement_count <= 0)::bigint
        FROM {relation}
        """
    )
    return cursor.fetchone()


def require_stage_integrity(cursor) -> None:
    cursor.execute(
        """
        SELECT count(*) FROM (
          SELECT 1 FROM _membership_receipt_movement_stage
          GROUP BY source_kind, receipt_date, source_group_recorder_id,
                   source_group_line_no, contract_id, accounting_analytics_text,
                   payment_type, client_key, access_club_id, sales_point_club_id,
                   contract_activation_date, contract_start_date, contract_end_date,
                   source_stage_id, source_product_name, source_product_freeze_days,
                   product_id, contract_term_days, purchase_type_id,
                   membership_kind_id, club_access_type_id, source_object
          HAVING count(*) > 1
        ) duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Duplicate current-M natural key in movement source stage")
    cursor.execute(
        """
        SELECT count(*) FROM _membership_receipt_movement_stage
        WHERE source_kind IS NULL OR receipt_date IS NULL OR reporting_club_id IS NULL
           OR payment_type IS NULL OR super_stage IS NULL OR amount_raw IS NULL
           OR amount_signed IS NULL OR co_access_amount IS NULL
           OR receipt_amount_net IS NULL OR source_movement_count <= 0
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Movement fact contract violation in source stage")
    cursor.execute(
        """
        SELECT count(*) FROM _membership_contract_kpi_unit_stage
        WHERE kpi_unit_key IS NULL OR kpi_unit_kind IS NULL OR contract_id IS NULL
           OR payment_type NOT IN ('Предоплата', 'Рекарринг') OR super_stage IS NULL
           OR calculation_mode IS NULL OR source_movement_count <= 0
           OR (kpi_unit_kind = 'recurring_payment' AND payment_period IS NULL)
           OR (kpi_unit_kind = 'prepayment_contract' AND payment_period IS NOT NULL)
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("KPI fact contract violation in source stage")


def copy_contract_attributes(source_cur, target_cur, contract_ids: list[str], start: date, end: date) -> None:
    """Fetch only the historical attributes required by the staged KPI contracts."""
    target_cur.execute("CREATE TEMP TABLE _membership_price_stage (contract_id text PRIMARY KEY, list_contract_price numeric) ON COMMIT DROP")
    target_cur.execute("CREATE TEMP TABLE _membership_freeze_stage (contract_id text PRIMARY KEY, free_freeze_before_activation_days numeric NOT NULL) ON COMMIT DROP")
    price_rows = freeze_rows = 0
    price_sql = """
        SELECT encode(a._fld7741rref, 'hex'), sum(a._fld7749::numeric)
        FROM public._accumrg7739 a
        WHERE a._fld7741rref = ANY(%s::bytea[])
          AND a._period >= DATE '2015-01-01' AND a._recordkind=0
        GROUP BY 1
    """
    freeze_sql = """
        SELECT encode(m._fld7479rref, 'hex'),
               greatest(sum(m._fld7481::numeric) FILTER (WHERE d266._idrref IS NOT NULL)
                        - coalesce(sum(m._fld7481::numeric) FILTER (WHERE orp._document315_idrref IS NOT NULL),0),0)::numeric
        FROM public._accumrg7478 m
        JOIN public._reference59 c ON c._idrref=m._fld7479rref
        LEFT JOIN public._document266 d266 ON d266._idrref=m._recorderrref
        LEFT JOIN public._document315_vt3894 orp
          ON orp._document315_idrref=m._recorderrref AND orp._fld3896rref=m._fld7479rref
        WHERE m._period >= %s::date AND m._period < %s::date AND m._recordkind=0
          AND m._period::date BETWEEN c._fld674::date AND c._fld670::date
        GROUP BY 1
    """
    for offset in range(0, len(contract_ids), 5_000):
        refs = [bytes.fromhex(contract_id) for contract_id in contract_ids[offset:offset + 5_000]]
        source_cur.execute(price_sql, (refs,))
        rows = source_cur.fetchall()
        price_rows += len(rows)
        with target_cur.copy("COPY _membership_price_stage (contract_id, list_contract_price) FROM STDIN WITH (FORMAT BINARY)") as copy:
            for row in rows:
                copy.write_row(row)
    source_cur.execute(freeze_sql, (start, end))
    rows = source_cur.fetchall()
    freeze_rows = len(rows)
    with target_cur.copy("COPY _membership_freeze_stage (contract_id, free_freeze_before_activation_days) FROM STDIN WITH (FORMAT BINARY)") as copy:
        for row in rows:
            copy.write_row(row)
    print(f"SOURCE_AUX contracts={len(contract_ids)} price_rows={price_rows} freeze_rows={freeze_rows}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform approved target DML")
    args = parser.parse_args()
    if not args.apply:
        raise SystemExit("Refusing DML without --apply")

    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    all_query = source_all_projection(start, end)
    history_query = source_history_projection(start, end)
    print(f"LOAD_STARTED horizon={start}..{end}", flush=True)

    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        with source.cursor() as source_cur, target.cursor() as target_cur:
            source_cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            target_cur.execute("BEGIN")
            target_cur.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.membership_receipts:refresh",))
            target_cur.execute("""CREATE TEMP TABLE _membership_source_stage (
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
            ) ON COMMIT DROP""")
            target_cur.execute("""CREATE TEMP TABLE _membership_contract_history_stage (
              contract_id text PRIMARY KEY, client_key text NOT NULL, activation_date date,
              start_date date, end_date date, payment_type text NOT NULL
            ) ON COMMIT DROP""")
            target_cur.execute("CREATE TEMP TABLE _membership_receipt_movement_stage (LIKE mart.membership_receipt_movement INCLUDING DEFAULTS) ON COMMIT DROP")
            target_cur.execute("CREATE TEMP TABLE _membership_contract_kpi_unit_stage (LIKE mart.membership_contract_kpi_unit INCLUDING DEFAULTS) ON COMMIT DROP")
            with target_cur.copy(f"COPY _membership_source_stage ({ALL_STAGE_COLUMNS}) FROM STDIN WITH (FORMAT BINARY)") as target_copy, source_cur.copy(f"COPY ({all_query}) TO STDOUT WITH (FORMAT BINARY)") as source_copy:
                for block in source_copy:
                    target_copy.write(block)
            with target_cur.copy("COPY _membership_contract_history_stage (contract_id, client_key, activation_date, start_date, end_date, payment_type) FROM STDIN WITH (FORMAT BINARY)") as target_copy, source_cur.copy(f"COPY ({history_query}) TO STDOUT WITH (FORMAT BINARY)") as source_copy:
                for block in source_copy:
                    target_copy.write(block)
            target_cur.execute("""
              WITH history_starts AS (
                SELECT client_key, start_date, min(contract_id) AS contract_id
                FROM _membership_contract_history_stage
                WHERE start_date IS NOT NULL AND end_date >= start_date
                GROUP BY 1,2
              ), predecessor AS (
                SELECT client_key, start_date,
                       lag(contract_id) OVER (PARTITION BY client_key ORDER BY start_date) AS previous_contract_id
                FROM history_starts
              ), predecessor_attr AS (
                SELECT p.client_key, p.start_date, h.end_date AS previous_end_date,
                       h.payment_type AS previous_payment_type
                FROM predecessor p
                LEFT JOIN _membership_contract_history_stage h ON h.contract_id=p.previous_contract_id
              )
              UPDATE _membership_source_stage s
              SET super_stage=CASE
                WHEN pa.previous_end_date IS NOT NULL AND s.contract_activation_date IS NOT NULL
                     AND date_trunc('month',pa.previous_end_date)=date_trunc('month',s.contract_activation_date)
                     AND pa.previous_payment_type='Рекарринг' THEN coalesce(s.source_stage,'NEW')
                WHEN pa.previous_end_date IS NOT NULL AND s.contract_activation_date IS NOT NULL
                     AND date_trunc('month',s.contract_activation_date)-date_trunc('month',pa.previous_end_date)>interval '0 months'
                     AND s.source_stage='RENEW' THEN 'RENEW(БП)'
                WHEN pa.previous_end_date IS NOT NULL AND s.contract_activation_date IS NOT NULL
                     AND s.contract_activation_date-pa.previous_end_date < -180 AND s.source_stage='EX' THEN 'NEW'
                WHEN s.source_stage IS NULL OR s.source_stage='NEW' THEN 'NEW'
                ELSE s.source_stage END
              FROM predecessor_attr pa
              WHERE s.payment_type='Предоплата'
                AND s.client_key=pa.client_key AND s.contract_start_date=pa.start_date
            """)
            target_cur.execute("""
              SELECT DISTINCT contract_id
              FROM _membership_source_stage
              WHERE row_type='movement' AND payment_type IN ('Предоплата','Рекарринг')
                AND contract_id IS NOT NULL
              ORDER BY 1
            """)
            kpi_contract_ids = [row[0] for row in target_cur.fetchall()]
            copy_contract_attributes(source_cur, target_cur, kpi_contract_ids, start, end)
            target_cur.execute(f"""INSERT INTO _membership_receipt_movement_stage ({MOVEMENT_COLUMNS})
                SELECT source_kind, source_object, receipt_date, source_group_recorder_id, source_group_line_no,
                       contract_id, client_key, analytics_text, payment_period, payment_type, movement_kind, recorder_type,
                       movement_club_id, access_club_id, sales_point_club_id, reporting_club_id, manager_id, product_id,
                       source_product_name, source_product_freeze_days, contract_activation_date, contract_start_date,
                       contract_end_date, contract_term_days, source_stage_id, source_stage, super_stage, payment_source,
                       product_age_category, purchase_type, purchase_type_id, membership_kind, membership_kind_id,
                       club_access_type, club_access_type_id, access_time_type, access_zone, amount_raw, amount_signed,
                       co_access_amount, receipt_amount_net, service_group, source_movement_count
                FROM _membership_source_stage WHERE row_type='movement'""")
            target_cur.execute(f"""INSERT INTO _membership_contract_kpi_unit_stage ({KPI_COLUMNS})
                WITH kpi_groups AS (
                  SELECT CASE WHEN payment_type='Рекарринг' THEN contract_id||':'||payment_period::text ELSE contract_id END AS kpi_unit_key,
                         CASE WHEN payment_type='Рекарринг' THEN 'recurring_payment' ELSE 'prepayment_contract' END AS kpi_unit_kind,
                         CASE WHEN payment_type='Рекарринг' THEN min(receipt_date) ELSE min(contract_activation_date) END AS metric_date,
                         contract_id, min(client_key) AS client_key,
                         CASE WHEN payment_type='Рекарринг' THEN payment_period END AS payment_period,
                         min(access_club_id) AS access_club_id, min(sales_point_club_id) AS sales_point_club_id,
                         min(manager_id) AS manager_id, min(product_id) AS product_id,
                         min(contract_activation_date) AS contract_activation_date,
                         min(contract_start_date) AS contract_start_date, min(contract_end_date) AS contract_end_date,
                         min(contract_term_days) AS contract_term_days, min(source_stage) AS source_stage,
                         min(super_stage) AS super_stage, payment_type, min(payment_source) AS payment_source,
                         min(product_age_category) AS product_age_category, min(purchase_type) AS purchase_type,
                         min(membership_kind) AS membership_kind, min(club_access_type) AS club_access_type,
                         min(access_time_type) AS access_time_type, min(access_zone) AS access_zone,
                         min(calculation_mode) AS calculation_mode,
                         sum(receipt_amount_net)::numeric AS net_receipt_amount,
                         sum(source_movement_count)::bigint AS source_movement_count
                  FROM _membership_source_stage
                  WHERE row_type='movement' AND payment_type IN ('Предоплата','Рекарринг')
                  GROUP BY payment_type, contract_id, payment_period
                )
                SELECT kg.kpi_unit_key, kg.kpi_unit_kind, kg.metric_date, kg.contract_id, kg.client_key,
                       kg.payment_period, kg.access_club_id, kg.sales_point_club_id, kg.manager_id, kg.product_id,
                       kg.contract_activation_date, kg.contract_start_date, kg.contract_end_date, kg.contract_term_days,
                       coalesce(f.free_freeze_before_activation_days,0)::numeric,
                       CASE WHEN kg.payment_type='Рекарринг' THEN 30.42::numeric
                            ELSE kg.contract_term_days+coalesce(f.free_freeze_before_activation_days,0) END,
                       kg.source_stage, kg.super_stage, kg.payment_type, kg.payment_source,
                       kg.product_age_category, kg.purchase_type, kg.membership_kind, kg.club_access_type,
                       kg.access_time_type, kg.access_zone, p.list_contract_price,
                       CASE WHEN kg.super_stage IN ('Продажа','Списание') OR kg.calculation_mode='Ф' THEN kg.net_receipt_amount
                            WHEN kg.calculation_mode='П' THEN p.list_contract_price ELSE NULL END,
                       kg.calculation_mode, kg.source_movement_count
                FROM kpi_groups kg
                LEFT JOIN _membership_price_stage p USING(contract_id)
                LEFT JOIN _membership_freeze_stage f USING(contract_id)
                WHERE kg.net_receipt_amount <> 0
                  AND kg.contract_end_date-kg.contract_start_date > 28""")

            require_stage_integrity(target_cur)
            movement_stage = movement_controls(target_cur, "_membership_receipt_movement_stage")
            kpi_stage = kpi_controls(target_cur, "_membership_contract_kpi_unit_stage")
            if not movement_stage[0] or not kpi_stage[0]:
                raise RuntimeError("Unexpected empty membership source stage")
            print(f"SOURCE_STAGE horizon={start}..{end} movement={movement_stage} kpi={kpi_stage}", flush=True)

            target_cur.execute("DELETE FROM mart.membership_receipt_movement")
            target_cur.execute("DELETE FROM mart.membership_contract_kpi_unit")
            target_cur.execute(f"INSERT INTO mart.membership_receipt_movement ({MOVEMENT_COLUMNS}) SELECT {MOVEMENT_COLUMNS} FROM _membership_receipt_movement_stage")
            target_cur.execute(f"INSERT INTO mart.membership_contract_kpi_unit ({KPI_COLUMNS}) SELECT {KPI_COLUMNS} FROM _membership_contract_kpi_unit_stage")
            movement_persisted = movement_controls(target_cur, "mart.membership_receipt_movement")
            kpi_persisted = kpi_controls(target_cur, "mart.membership_contract_kpi_unit")
            if movement_persisted != movement_stage or kpi_persisted != kpi_stage:
                raise RuntimeError("Persisted controls differ from the staged source snapshot")
            target.commit()
            print(f"DML_COMMITTED movement={movement_persisted} kpi={kpi_persisted}", flush=True)
            source.rollback()


if __name__ == "__main__":
    main()
