#!/usr/bin/env python3
"""Guarded source-first loader for mart.fitness_funnel_client_outcome.

The physical-admission runner keeps only bounded, derived target-column COPY
files. It never creates a raw 1C replica and opens the target transaction only
after every source month has been prepared from one exported snapshot.
"""
from __future__ import annotations

import argparse
import sys
import tempfile
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.load_children_package_sale import config
from scripts.mart_connection import connect_with_retry

EXTRACT = ROOT / "sql/marts/fitness_funnel_client_outcome_source_extract.sql"
CONTROLS = ROOT / "sql/marts/fitness_funnel_client_outcome_source_controls.sql"
DDL = ROOT / "sql/marts/fitness_funnel_client_outcome_ddl.sql"
RECON = ROOT / "sql/tests/fitness_funnel_client_outcome_reconciliation.sql"
TABLE = "mart.fitness_funnel_client_outcome"
STAGE = "_fitness_funnel_client_outcome_stage"
COLUMNS = "outcome_source_key,client_key,outcome_date,outcome_type,club_id,service_id,employee_id,outcome_count"
TOKEN = "FFCOUTCOME_PHYSICAL_ADMISSION_REQUIRED"
SOURCE_BATCH_ATTEMPTS = 5
SOURCE_POOL_ATTEMPTS = 3
TARGET_ATTEMPTS = 5
OPTIONS = {"connect_timeout": 15, "keepalives": 1, "keepalives_idle": 60,
           "keepalives_interval": 15, "keepalives_count": 4, "tcp_user_timeout": 180_000}


@dataclass(frozen=True)
class PreparedBatch:
    start: date
    end: date
    path: Path
    rows: int
    bytes: int
    elapsed_seconds: float
    expected: dict[str, int]


def source_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(lambda: psycopg.connect(**(config("SOURCE_") | OPTIONS | {"application_name": name})), endpoint="source")


def target_connection(name: str) -> psycopg.Connection:
    return connect_with_retry(lambda: psycopg.connect(**(config("MART_") | OPTIONS | {"application_name": name})), endpoint="mart")


def render(path: Path, start: date, end: date) -> str:
    return (path.read_text(encoding="utf-8").strip().rstrip(";")
            .replace("$1::date", f"DATE '{start.isoformat()}'")
            .replace("$2::date", f"DATE '{end.isoformat()}'"))


def statements(path: Path) -> list[str]:
    body = "\n".join(line for line in path.read_text(encoding="utf-8").splitlines()
                     if not line.lstrip().startswith("--"))
    return [part.strip() for part in body.split(";") if part.strip()]


def month_batches(start: date, end: date) -> list[tuple[date, date]]:
    result: list[tuple[date, date]] = []
    current = start
    while current < end:
        following = date(current.year + (current.month == 12), current.month % 12 + 1, 1)
        result.append((current, min(following, end)))
        current = following
    return result


def close_after_failure(connection: psycopg.Connection | None) -> None:
    if connection is None:
        return
    try:
        connection.rollback()
    except Exception:
        pass
    try:
        connection.close()
    except Exception:
        pass


def source_contract(cursor: psycopg.Cursor, start: date, end: date) -> dict[str, int]:
    results: list[dict[str, object]] = []
    for statement in statements(CONTROLS):
        cursor.execute(statement.replace("$1::date", f"DATE '{start.isoformat()}'").replace("$2::date", f"DATE '{end.isoformat()}'"))
        columns = tuple(column.name for column in cursor.description)
        results.extend(dict(zip(columns, row, strict=True)) for row in cursor.fetchall())
    first = next(row for row in results if row["control_id"] == "FF-O01")
    second = next(row for row in results if row["control_id"] == "FF-O02")
    if any(int(first[key]) != 0 for key in ("duplicate_source_keys", "required_null_rows", "horizon_rows")):
        raise RuntimeError(f"FF-O01 failed: {first}")
    if int(second["duplicate_physical_keys"]) != 0:
        raise RuntimeError(f"FF-O02 failed: {second}")
    expected = {str(row["branch"]): int(row["expected_rows"])
                for row in results if row["control_id"] == "FF-O03"}
    required = {"DPFU7575", "DPFU7646", "IPPZ", "IPGZ", "SPT"}
    if set(expected) != required or any(value < 0 for value in expected.values()):
        raise RuntimeError(f"FF-O03 incomplete independent expected controls: {expected}")
    return expected


def open_snapshot_owner() -> tuple[psycopg.Connection, str]:
    owner = source_connection("fitness_funnel_outcome_snapshot_owner")
    try:
        with owner.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout='300s'")
            cursor.execute("SET LOCAL work_mem='64MB'")
            cursor.execute("SELECT pg_export_snapshot()")
            return owner, str(cursor.fetchone()[0])
    except Exception:
        close_after_failure(owner)
        raise


def open_snapshot_reader(snapshot_id: str) -> psycopg.Connection:
    reader = source_connection("fitness_funnel_outcome_source_batch")
    try:
        with reader.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout='300s'")
            cursor.execute("SET LOCAL work_mem='64MB'")
            cursor.execute(sql.SQL("SET TRANSACTION SNAPSHOT {}").format(sql.Literal(snapshot_id)))
        return reader
    except Exception:
        close_after_failure(reader)
        raise


def prepare_source_batch(snapshot_id: str, start: date, end: date, directory: Path, remaining_cap: int) -> PreparedBatch:
    path = directory / f"fitness_funnel_outcome_{start:%Y%m}.copy"
    for attempt in range(1, SOURCE_BATCH_ATTEMPTS + 1):
        reader: psycopg.Connection | None = None
        path.unlink(missing_ok=True)
        try:
            reader = open_snapshot_reader(snapshot_id)
            with reader.cursor() as cursor:
                expected = source_contract(cursor, start, end)
                expected_rows = sum(expected.values())
                started = time.monotonic()
                with path.open("wb") as output, cursor.copy(f"COPY ({render(EXTRACT, start, end)}) TO STDOUT (FORMAT BINARY)") as copied:
                    for block in copied:
                        output.write(block)
                        if output.tell() > remaining_cap:
                            raise RuntimeError("aggregate derived COPY cap would be exceeded")
                rows = cursor.rowcount
                elapsed = time.monotonic() - started
            reader.rollback()
            reader.close()
            if rows != expected_rows:
                raise RuntimeError(f"source batch differs from independent controls: {rows} != {expected_rows}")
            return PreparedBatch(start, end, path, rows, path.stat().st_size, elapsed, expected)
        except psycopg.OperationalError as error:
            close_after_failure(reader)
            path.unlink(missing_ok=True)
            if attempt == SOURCE_BATCH_ATTEMPTS:
                raise
            print(f"SOURCE_BATCH_RETRY start={start} retry={attempt}/{SOURCE_BATCH_ATTEMPTS - 1} error={type(error).__name__}", flush=True)
            time.sleep(5)
        except Exception:
            close_after_failure(reader)
            path.unlink(missing_ok=True)
            raise
    raise AssertionError("unreachable")


def prepare_source_pool(start: date, end: date, directory: Path, cap: int) -> list[PreparedBatch]:
    for attempt in range(1, SOURCE_POOL_ATTEMPTS + 1):
        for leftover in directory.glob("fitness_funnel_outcome_*.copy"):
            leftover.unlink(missing_ok=True)
        owner: psycopg.Connection | None = None
        prepared: list[PreparedBatch] = []
        try:
            owner, snapshot_id = open_snapshot_owner()
            print(f"SOURCE_SNAPSHOT horizon=[{start},{end}) mode=source-first-monthly", flush=True)
            total_bytes = 0
            for batch_start, batch_end in month_batches(start, end):
                batch = prepare_source_batch(snapshot_id, batch_start, batch_end, directory, cap - total_bytes)
                total_bytes += batch.bytes
                prepared.append(batch)
                print({"phase": "source_batch", "window": f"[{batch.start},{batch.end})", "rows": batch.rows,
                       "bytes": batch.bytes, "expected_by_branch": batch.expected}, flush=True)
            try:
                owner.rollback()
            except psycopg.OperationalError as error:
                # Every batch reader has already consumed the exported snapshot
                # successfully.  A VPN failure only while closing the owner
                # cannot change those completed derived files.
                print(f"SOURCE_OWNER_CLOSE_UNAVAILABLE error={type(error).__name__}", flush=True)
            finally:
                close_after_failure(owner)
            return prepared
        except psycopg.OperationalError as error:
            close_after_failure(owner)
            for batch in prepared:
                batch.path.unlink(missing_ok=True)
            if attempt == SOURCE_POOL_ATTEMPTS:
                raise
            print(f"SOURCE_POOL_RETRY retry={attempt}/{SOURCE_POOL_ATTEMPTS - 1} error={type(error).__name__}", flush=True)
            time.sleep(5)
        except Exception:
            close_after_failure(owner)
            for batch in prepared:
                batch.path.unlink(missing_ok=True)
            raise
    raise AssertionError("unreachable")


def expected_total(batches: list[PreparedBatch]) -> dict[str, int]:
    result = {"DPFU7575": 0, "DPFU7646": 0, "IPPZ": 0, "IPGZ": 0, "SPT": 0}
    for batch in batches:
        for branch, value in batch.expected.items():
            result[branch] += value
    return result


def require_stage_contract(cursor: psycopg.Cursor, expected: dict[str, int], start: date, end: date) -> None:
    cursor.execute(f"""SELECT count(*)::bigint, count(DISTINCT outcome_source_key)::bigint,
        count(*) FILTER (WHERE client_key IS NULL OR outcome_date IS NULL OR club_id IS NULL OR service_id IS NULL OR employee_id IS NULL OR outcome_count<>1)::bigint,
        count(*) FILTER (WHERE outcome_date < DATE '{start.isoformat()}' OR outcome_date >= DATE '{end.isoformat()}')::bigint,
        count(*) FILTER (WHERE outcome_source_key LIKE 'DPFU7575:%')::bigint,
        count(*) FILTER (WHERE outcome_source_key LIKE 'DPFU7646:%')::bigint,
        count(*) FILTER (WHERE outcome_source_key LIKE 'IPPZ:%')::bigint,
        count(*) FILTER (WHERE outcome_source_key LIKE 'IPGZ:%')::bigint,
        count(*) FILTER (WHERE outcome_source_key LIKE 'SPT:%')::bigint
        FROM {STAGE}""")
    actual = tuple(int(value) for value in cursor.fetchone())
    required = (sum(expected.values()), sum(expected.values()), 0, 0,
                expected["DPFU7575"], expected["DPFU7646"], expected["IPPZ"], expected["IPGZ"], expected["SPT"])
    if actual != required:
        raise RuntimeError(f"stage differs from independent controls actual={actual} expected={required}")


def reconciliation_sql(expected: dict[str, int], start: date, end: date) -> str:
    replacements = {
        "$1": str(sum(expected.values())), "$2::date": f"DATE '{start.isoformat()}'",
        "$3::date": f"DATE '{end.isoformat()}'", "$4": str(expected["DPFU7575"]),
        "$5": str(expected["DPFU7646"]), "$6": str(expected["IPPZ"]),
        "$7": str(expected["IPGZ"]), "$8": str(expected["SPT"]),
    }
    statement = RECON.read_text(encoding="utf-8").strip().rstrip(";")
    for marker, value in replacements.items():
        statement = statement.replace(marker, value)
    return statement


def load_atomic(batches: list[PreparedBatch], expected: dict[str, int], start: date, end: date) -> list[str]:
    for attempt in range(1, TARGET_ATTEMPTS + 1):
        target: psycopg.Connection | None = None
        try:
            target = target_connection("fitness_funnel_outcome_target")
            with target.cursor() as cursor, target.transaction():
                cursor.execute("SET LOCAL lock_timeout='60s'")
                cursor.execute("SET LOCAL idle_in_transaction_session_timeout='240s'")
                cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (TABLE,))
                cursor.execute("SELECT to_regclass(%s)", (TABLE,))
                if cursor.fetchone()[0] is None:
                    cursor.execute(DDL.read_text(encoding="utf-8"))
                cursor.execute(f"CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP")
                for batch in batches:
                    with batch.path.open("rb") as input_file, cursor.copy(f"COPY {STAGE} ({COLUMNS}) FROM STDIN (FORMAT BINARY)") as copied:
                        while block := input_file.read(1_048_576):
                            copied.write(block)
                    if cursor.rowcount != batch.rows:
                        raise RuntimeError(f"target batch COPY differs: {cursor.rowcount} != {batch.rows}")
                    print({"phase": "target_batch", "window": f"[{batch.start},{batch.end})", "rows": batch.rows, "bytes": batch.bytes}, flush=True)
                require_stage_contract(cursor, expected, start, end)
                cursor.execute(f"DELETE FROM {TABLE}")
                cursor.execute(f"INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM {STAGE}")
                cursor.execute(reconciliation_sql(expected, start, end))
                results = cursor.fetchall()
                failures = [row for row in results if row[3] != "PASS"]
                if failures:
                    raise RuntimeError(f"target reconciliation failed: {failures}")
                return [str(row[0]) for row in results]
        except psycopg.OperationalError as error:
            close_after_failure(target)
            if attempt == TARGET_ATTEMPTS:
                raise
            print(f"TARGET_ATOMIC_RETRY retry={attempt}/{TARGET_ATTEMPTS - 1} error={type(error).__name__}", flush=True)
            time.sleep(5)
        except Exception:
            close_after_failure(target)
            raise
        finally:
            if target is not None:
                target.close()
    raise AssertionError("unreachable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--admission-token", required=True)
    parser.add_argument("--start", type=date.fromisoformat, default=date(2024, 1, 1))
    parser.add_argument("--end", type=date.fromisoformat,
                        default=datetime.now(ZoneInfo("Europe/Moscow")).date() + timedelta(days=1))
    parser.add_argument("--max-derived-bytes", type=int, required=True,
                        help="aggregate cap for the complete monthly derived COPY pool")
    args = parser.parse_args()
    if args.admission_token != TOKEN:
        raise SystemExit("physical admission token required")
    if args.start >= args.end or args.max_derived_bytes <= 0:
        raise SystemExit("invalid horizon or cap")
    with tempfile.TemporaryDirectory(prefix="fitness_funnel_outcome_") as temporary_directory:
        batches = prepare_source_pool(args.start, args.end, Path(temporary_directory), args.max_derived_bytes)
        expected = expected_total(batches)
        print({"phase": "source_pool_ready", "batches": len(batches), "rows": sum(expected.values()),
               "bytes": sum(batch.bytes for batch in batches), "expected_by_branch": expected}, flush=True)
        controls = load_atomic(batches, expected, args.start, args.end)
        print({"phase": "target_commit", "table": TABLE, "controls": controls}, flush=True)


if __name__ == "__main__":
    main()
