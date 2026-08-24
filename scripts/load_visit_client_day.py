#!/usr/bin/env python3
"""Atomically rebuild mart.visit_client_day from read-only 1C."""

import argparse
import os
import sys
import time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
EXTRACT = ROOT / "sql/marts/visit_client_day_extract.sql"
COLUMNS = """visit_date, club_id, client_key, has_visit,
has_member_visit, has_guest_visit, has_vip_visit,
has_drc_visit, has_after_school_visit, has_umnyashki_visit""".replace("\n", " ")
TARGET = os.environ.get("VISIT_CLIENT_DAY_TARGET", "mart.visit_client_day")


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    missing = [prefix + name for name in names if not os.environ.get(prefix + name)]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result = {"host": os.environ[prefix + "PGHOST"], "port": os.environ[prefix + "PGPORT"],
              "dbname": os.environ[prefix + "PGDATABASE"], "user": os.environ[prefix + "PGUSER"],
              "password": os.environ[prefix + "PGPASSWORD"]}
    if prefix == "SOURCE_" and os.environ.get("SOURCE_PGSSLMODE"):
        result["sslmode"] = os.environ["SOURCE_PGSSLMODE"]
    return result


def horizon() -> tuple[date, date]:
    today = datetime.now(ZoneInfo("Europe/Moscow")).date()
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date(today.year + 1, 1, 1)


def projection(start: date, end: date) -> str:
    return EXTRACT.read_text(encoding="utf-8").strip().rstrip(";").replace(
        "$1::date", f"DATE '{start.isoformat()}'").replace("$2::date", f"DATE '{end.isoformat()}'")


def next_chunk(day: date, limit: date, months: int) -> date:
    month = day.month + months
    year = day.year + (month - 1) // 12
    month = (month - 1) % 12 + 1
    return min(date(year, month, 1), limit)


def controls(cur, relation: str) -> tuple[object, ...]:
    cur.execute(f"""SELECT count(*)::bigint,
        count(*) FILTER (WHERE has_visit)::bigint,
        count(*) FILTER (WHERE has_member_visit)::bigint,
        count(*) FILTER (WHERE has_guest_visit)::bigint,
        count(*) FILTER (WHERE has_vip_visit)::bigint,
        count(*) FILTER (WHERE has_drc_visit)::bigint,
        count(*) FILTER (WHERE has_after_school_visit)::bigint,
        count(*) FILTER (WHERE has_umnyashki_visit)::bigint,
        count(*) FILTER (WHERE visit_date IS NULL OR club_id IS NULL OR client_key IS NULL)::bigint
        FROM {relation}""")
    return cur.fetchone()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform approved target DML")
    parser.add_argument("--append", action="store_true", help="append to an approved temporary loading relation")
    parser.add_argument("--start", type=date.fromisoformat, help="inclusive ISO date; defaults to BR-003")
    parser.add_argument("--end", type=date.fromisoformat, help="exclusive ISO date; defaults to BR-003")
    parser.add_argument(
        "--chunk-months", type=int, default=6,
        help="months per source-to-target COPY block; defaults to 6",
    )
    args = parser.parse_args()
    if not args.apply:
        raise SystemExit("Refusing DML without --apply")
    default_start, default_end = horizon()
    start, end = args.start or default_start, args.end or default_end
    if start >= end:
        raise SystemExit("--start must be earlier than --end")
    if args.chunk_months < 1 or args.chunk_months > 12:
        raise SystemExit("--chunk-months must be between 1 and 12")
    begin = time.monotonic()
    with connect_with_retry(lambda: psycopg.connect(**config("SOURCE_")), endpoint="source") as source, \
         connect_with_retry(lambda: psycopg.connect(**config("MART_")), endpoint="mart") as target:
        with source.cursor() as source_cur, target.cursor() as target_cur:
            source_cur.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            target_cur.execute("BEGIN")
            target_cur.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (f"{TARGET}:refresh",))
            existing_rows = controls(target_cur, TARGET)[0] if args.append else 0
            if not args.append:
                target_cur.execute(f"TRUNCATE {TARGET}")
            chunk_start = start
            copied_source_rows = 0
            copied_target_rows = 0
            while chunk_start < end:
                chunk_end = next_chunk(chunk_start, end, args.chunk_months)
                query = projection(chunk_start, chunk_end)
                chunk_started = time.monotonic()
                copy_out = f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)"
                copy_in = f"COPY {TARGET} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
                with source_cur.copy(copy_out) as from_source, target_cur.copy(copy_in) as to_target:
                    while data := from_source.read():
                        to_target.write(data)
                source_rows, target_rows = source_cur.rowcount, target_cur.rowcount
                if source_rows != target_rows:
                    raise RuntimeError(f"COPY row count mismatch source={source_rows} target={target_rows}")
                copied_source_rows += source_rows
                copied_target_rows += target_rows
                print(f"SOURCE_TARGET_COPY_CHUNK {chunk_start}..{chunk_end} rows={source_rows} elapsed_seconds={time.monotonic()-chunk_started:.3f}", flush=True)
                chunk_start = chunk_end
            if copied_source_rows != copied_target_rows:
                raise RuntimeError("Total COPY row counts differ")
            target_write_started = time.monotonic()
            persisted = controls(target_cur, TARGET)
            if not persisted[0] or persisted[-1]:
                raise RuntimeError(f"Target contract violation rows={persisted[0]} nulls={persisted[-1]}")
            if persisted[0] != existing_rows + copied_target_rows:
                raise RuntimeError(f"Target count differs from COPY count target={persisted[0]} expected={existing_rows + copied_target_rows}")
            print(f"TARGET_CONTROL elapsed_seconds={time.monotonic()-target_write_started:.3f}", flush=True)
            commit_started = time.monotonic()
            target.commit()
            source.rollback()
            print(f"COMMIT elapsed_seconds={time.monotonic()-commit_started:.3f}", flush=True)
    print(f"DML_COMMITTED target={TARGET} horizon={start}..{end} copy_rows={copied_target_rows} controls={persisted} elapsed_seconds={time.monotonic()-begin:.3f}")


if __name__ == "__main__":
    main()
