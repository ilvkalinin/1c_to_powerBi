#!/usr/bin/env python3
"""Atomically rebuild mart.administrator_card_gymmy_daily after approval."""
from __future__ import annotations

import argparse
import os
import time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/administrator_card_gymmy_daily_extract.sql"
SOURCE_CONTROLS = ROOT / "sql/marts/administrator_card_gymmy_daily_source_controls.sql"
TARGET_REPLACE = ROOT / "sql/marts/administrator_card_gymmy_daily_target_replace.sql"
COLUMNS = "event_date, club_id, direction, usage_count"
CARD_CODES = (
    "И00134834", "001365180", "001365168", "001365170", "001365171", "001365172",
    "001365174", "001365175", "001365177", "001365178", "001365167", "001365166",
)


def config(prefix: str) -> dict[str, str]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"Missing configuration: {', '.join(missing)}")
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"],
        "dbname": values["PGDATABASE"], "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
    }
    sslmode = os.environ.get(prefix + "PGSSLMODE")
    if sslmode:
        result["sslmode"] = sslmode
    return result


def connect_with_retry(prefix: str):
    for attempt in range(1, 4):
        try:
            return psycopg.connect(**config(prefix), connect_timeout=15)
        except psycopg.OperationalError:
            if attempt == 3:
                raise
            print(f"{prefix}CONNECTION_RETRY attempt={attempt + 1}/3", flush=True)
            time.sleep(3)


def br003_horizon(today: date) -> tuple[date, date]:
    return date(today.year - (2 if today.month <= 3 else 1), 1, 1), date(today.year + 1, 1, 1)


def rendered(path: Path, start: date, end: date) -> str:
    return path.read_text(encoding="utf-8").strip().rstrip(";").replace(
        "$1::date", f"DATE '{start.isoformat()}'"
    ).replace("$2::date", f"DATE '{end.isoformat()}'")


def source_direction_totals(cursor, query: str) -> dict[str, int]:
    cursor.execute(query)
    result = {direction: count for direction, count in cursor.fetchall()}
    if not result or set(result) - {"Вход", "Выход"}:
        raise RuntimeError(f"Unexpected source directions: {sorted(result)}")
    return result


def assert_card_mapping(cursor) -> None:
    cursor.execute(
        """WITH requested_cards(card_code) AS (VALUES """
        + ", ".join(["(%s)"] * len(CARD_CODES))
        + """), labels AS (
              SELECT q.card_code,
                     nullif(regexp_replace(trim(r._description::text), '^.*\\s+', ''), '') AS club_label
              FROM requested_cards q
              LEFT JOIN public._reference141x1 r ON r._code::text = q.card_code
          ), matches AS (
              SELECT l.card_code, count(c._idrref) AS club_matches
              FROM labels l LEFT JOIN public._reference132 c ON c._description::text = l.club_label
              GROUP BY l.card_code
          )
          SELECT count(*) FILTER (WHERE club_matches = 1),
                 count(*) FILTER (WHERE club_matches = 0),
                 count(*) FILTER (WHERE club_matches > 1)
          FROM matches""",
        CARD_CODES,
    )
    exact, missing, multiple = cursor.fetchone()
    if (exact, missing, multiple) != (len(CARD_CODES), 0, 0):
        raise RuntimeError(
            f"Card-to-club mapping is no longer one-to-one: exact={exact}, missing={missing}, multiple={multiple}"
        )


def target_direction_totals(cursor, relation: str) -> dict[str, int]:
    cursor.execute(
        f"SELECT direction, sum(usage_count)::bigint FROM {relation} GROUP BY direction ORDER BY direction"
    )
    return {direction: count for direction, count in cursor.fetchall()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="perform separately approved target DDL/DML")
    if not parser.parse_args().apply:
        raise SystemExit("Refusing DDL/DML without --apply")

    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    extract = rendered(EXTRACT, start, end)
    source_controls = rendered(SOURCE_CONTROLS, start, end)
    target_statements = [statement.strip() for statement in rendered(TARGET_REPLACE, start, end).split(";") if statement.strip()]
    if len(target_statements) != 4:
        raise RuntimeError("Unexpected target replacement statement count")

    with connect_with_retry("SOURCE_") as source, connect_with_retry("MART_") as target:
        with source.cursor() as source_cursor, target.cursor() as target_cursor:
            source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            target_cursor.execute("BEGIN")
            target_cursor.execute(
                "SELECT pg_advisory_xact_lock(hashtext(%s))",
                ("mart.administrator_card_gymmy_daily:refresh",),
            )
            assert_card_mapping(source_cursor)
            expected = source_direction_totals(source_cursor, source_controls)
            print(f"SOURCE_SNAPSHOT horizon={start}..{end} direction_totals={expected}", flush=True)
            target_cursor.execute(target_statements[0])
            with target_cursor.copy(
                f"COPY _administrator_card_gymmy_daily_stage ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)"
            ) as target_copy, source_cursor.copy(
                f"COPY ({extract}) TO STDOUT WITH (FORMAT BINARY)"
            ) as source_copy:
                for block in source_copy:
                    target_copy.write(block)
            target_cursor.execute(
                "SELECT count(*) FROM _administrator_card_gymmy_daily_stage "
                "WHERE event_date < %s OR event_date >= %s",
                (start, end),
            )
            if target_cursor.fetchone()[0]:
                raise RuntimeError("Stage contains rows outside BR-003 horizon")
            for statement in target_statements[1:]:
                target_cursor.execute(statement)
            actual = target_direction_totals(target_cursor, "mart.administrator_card_gymmy_daily")
            if actual != expected:
                raise RuntimeError(f"Persistent direction totals differ: {actual} != {expected}")
            target_cursor.execute(
                "SELECT count(*) FROM mart.administrator_card_gymmy_daily "
                "WHERE event_date < %s OR event_date >= %s OR usage_count <= 0",
                (start, end),
            )
            if target_cursor.fetchone()[0]:
                raise RuntimeError("Persistent table violates horizon or usage-count contract")
            target.commit()
            source.rollback()
            print(f"DML_COMMITTED horizon={start}..{end} direction_totals={actual}", flush=True)


if __name__ == "__main__":
    main()
