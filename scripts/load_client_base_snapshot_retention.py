#!/usr/bin/env python3
"""Atomically create/rebuild the package-aware client-base snapshot and retention facts."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
import psycopg2


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry, load_project_env

SNAPSHOT_EXTRACT = ROOT / "sql/marts/client_base_snapshot_extract.sql"
RETENTION_EXTRACT = ROOT / "sql/marts/client_base_retention_extract.sql"
SNAPSHOT_CONTROLS = ROOT / "sql/marts/client_base_daily_source_controls.sql"
RETENTION_CONTROLS = ROOT / "sql/marts/client_base_retention_source_control.sql"
SNAPSHOT_DDL = ROOT / "sql/marts/client_base_snapshot_ddl.sql"
RETENTION_DDL = ROOT / "sql/marts/client_base_retention_ddl.sql"
SNAPSHOT_REPLACE = ROOT / "sql/marts/client_base_snapshot_target_replace.sql"
RETENTION_REPLACE = ROOT / "sql/marts/client_base_retention_target_replace.sql"
RECONCILIATION = ROOT / "sql/tests/client_base_snapshot_retention_reconciliation.sql"
SNAPSHOT_COLUMNS = (
    "scope_level, report_date, club_id, age_years, age_group, gender, "
    "membership_tenure, activity_bucket, client_count"
)
RETENTION_COLUMNS = (
    "scope_level, report_date, comparison_type, comparison_date, baseline_club_id, "
    "current_age_years, current_age_group, current_gender, current_membership_tenure, "
    "baseline_client_count, retained_client_count"
)
TRANSPORT_TIMEOUT_SECONDS = 180
SOURCE_BATCH_MAX_ATTEMPTS = 3
TRANSPORT_PREFLIGHT_SAMPLES = 3
TRANSPORT_PREFLIGHT_INTERVAL_SECONDS = 10
TRANSPORT_CONNECTION_OPTIONS = {
    # These values also prevent an idle exported-snapshot owner or target
    # transaction from remaining half-open for hours.
    "keepalives": 1,
    "keepalives_idle": 60,
    "keepalives_interval": 15,
    "keepalives_count": 4,
    "tcp_user_timeout": 180_000,
    # libpq otherwise allows an unavailable tunnel admission to wait without
    # a bound; retries below always create a new socket.
    "connect_timeout": 15,
}


class TransportRestartRequired(RuntimeError):
    """The atomic target transaction is no longer usable after link loss."""


load_project_env()


class TransportWatchdog:
    """Cancel a stalled COPY through libpq's separate cancel channel."""

    def __init__(self, connection, phase: str):
        self.connection = connection
        self.phase = phase
        self.done = threading.Event()
        self.thread = threading.Thread(target=self._cancel_if_stalled, daemon=True)

    def _cancel_if_stalled(self) -> None:
        if not self.done.wait(TRANSPORT_TIMEOUT_SECONDS):
            print(f"TRANSPORT_TIMEOUT phase={self.phase} seconds={TRANSPORT_TIMEOUT_SECONDS}", flush=True)
            try:
                self.connection.cancel()
            except Exception as error:
                print(f"TRANSPORT_CANCEL_ERROR phase={self.phase} error={type(error).__name__}", flush=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_exc) -> None:
        self.done.set()
        self.thread.join(timeout=1)


def config(prefix: str, application_name: str | None = None) -> dict[str, str]:
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
    if sslmode := os.environ.get(prefix + "PGSSLMODE"):
        result["sslmode"] = sslmode
    if application_name:
        # Makes a stalled refresh attributable in pg_stat_activity without
        # revealing endpoint credentials in the execution log.
        result["application_name"] = application_name
    return result


def source_config(application_name: str) -> dict[str, object]:
    return config("SOURCE_", application_name) | TRANSPORT_CONNECTION_OPTIONS


def mart_config(application_name: str) -> dict[str, object]:
    return config("MART_", application_name) | TRANSPORT_CONNECTION_OPTIONS


def connect_source_with_retry(application_name: str):
    """Reconnect readers after a broken source transport, never reuse it."""
    last_error: Exception | None = None
    for retry in range(6):
        try:
            return psycopg2.connect(**source_config(application_name))
        except psycopg2.OperationalError as error:
            last_error = error
            if retry == 5:
                break
            print(
                f"CONNECTION_RETRY endpoint=source retry={retry + 1}/5 delay_seconds=5",
                flush=True,
            )
            time.sleep(5)
    assert last_error is not None
    raise last_error


def source_reader(snapshot_id: str):
    """Open one bounded reader against the single exported source snapshot."""
    connection = connect_source_with_retry("client_base_snapshot_retention_source_reader")
    try:
        with connection.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET TRANSACTION SNAPSHOT %s", (snapshot_id,))
            cursor.execute("SET LOCAL statement_timeout = '180000'")
        return connection
    except Exception:
        connection.close()
        raise


def source_admission_available() -> bool:
    """Check one fresh source socket before retrying a failed batch reader."""
    try:
        connection = psycopg2.connect(
            **source_config("client_base_snapshot_retention_source_admission_probe")
        )
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            return True
        finally:
            connection.close()
    except psycopg2.Error as error:
        print(
            f"SOURCE_ADMISSION_UNAVAILABLE error={type(error).__name__}",
            flush=True,
        )
        return False


def transport_preflight(endpoint: str) -> None:
    """Require several clean admission/query samples before the long phase.

    A full source snapshot is intentionally not retried blindly.  This check
    is cheap, read-only, and catches a tunnel that is still flapping before it
    can invalidate a long exported snapshot or start a target transaction.
    """
    for sample in range(1, TRANSPORT_PREFLIGHT_SAMPLES + 1):
        if endpoint == "source":
            connection = connect_source_with_retry("client_base_snapshot_retention_source_preflight")
        else:
            connection = connect_with_retry(
                lambda: psycopg.connect(**mart_config("client_base_snapshot_retention_target_preflight")),
                endpoint="mart",
            )
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            print(
                f"TRANSPORT_PREFLIGHT_PASS endpoint={endpoint} "
                f"sample={sample}/{TRANSPORT_PREFLIGHT_SAMPLES}",
                flush=True,
            )
        finally:
            connection.close()
        if sample < TRANSPORT_PREFLIGHT_SAMPLES:
            time.sleep(TRANSPORT_PREFLIGHT_INTERVAL_SECONDS)


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    return date(today.year - years_back, 1, 1), date.fromordinal(today.toordinal() + 1)


def rendered(path: Path, start: date, end: date) -> str:
    return (
        path.read_text(encoding="utf-8").strip().rstrip(";")
        .replace("$1::date", f"DATE '{start.isoformat()}'")
        .replace("$2::date", f"DATE '{end.isoformat()}'")
    )


def statements(path: Path, start: date, end: date) -> list[str]:
    body = "\n".join(
        line for line in rendered(path, start, end).splitlines()
        if not line.lstrip().startswith("--")
    )
    parts: list[str] = []
    current: list[str] = []
    in_literal = False
    index = 0
    while index < len(body):
        character = body[index]
        current.append(character)
        if character == "'":
            if in_literal and index + 1 < len(body) and body[index + 1] == "'":
                current.append(body[index + 1])
                index += 1
            else:
                in_literal = not in_literal
        elif character == ";" and not in_literal:
            statement = "".join(current[:-1]).strip()
            if statement and statement.upper() not in {"BEGIN", "COMMIT"}:
                parts.append(statement)
            current = []
        index += 1
    tail = "".join(current).strip()
    if tail and tail.upper() not in {"BEGIN", "COMMIT"}:
        parts.append(tail)
    return parts


def month_batches(start: date, end: date) -> list[tuple[date, date]]:
    batches: list[tuple[date, date]] = []
    batch_start = start
    while batch_start < end:
        next_month = date(
            batch_start.year + (batch_start.month == 12),
            batch_start.month % 12 + 1,
            1,
        )
        batches.append((batch_start, min(next_month, end)))
        batch_start = next_month
    return batches


def report_dates(start: date, end: date) -> set[date]:
    return {
        start + timedelta(days=offset)
        for offset in range((end - start).days)
        if (start + timedelta(days=offset)).isoweekday() == 1
        or (start + timedelta(days=offset)).day == 1
    }


def require_batch_space(directory: Path) -> None:
    if shutil.disk_usage(directory).free < 1_073_741_824:
        raise RuntimeError("Less than 1 GiB is free for the single COPY buffer")


def copy_source_batch(source, extract: Path, start: date, end: date, path: Path) -> tuple[int | None, int, float]:
    started_at = time.monotonic()
    with TransportWatchdog(source, "source_binary_copy"), source.cursor() as cursor, path.open("wb") as output:
        cursor.copy_expert(f"COPY ({rendered(extract, start, end)}) TO STDOUT WITH (FORMAT BINARY)", output)
        rows = cursor.rowcount if cursor.rowcount >= 0 else None
    return rows, path.stat().st_size, time.monotonic() - started_at


def snapshot_expected(cursor, sql: str, start: date, end: date) -> dict[tuple[date, str], int]:
    cursor.execute(sql)
    eligible = report_dates(start, end)
    result = {(day, scope): count for day, scope, count in cursor if day in eligible}
    expected_count = len(eligible) * 2
    if len(result) != expected_count or any(count <= 0 for count in result.values()):
        raise RuntimeError("Snapshot independent controls are incomplete or invalid")
    return result


def retention_expected(cursor, sql: str) -> dict[tuple[date, str, date, str], tuple[int, int]]:
    cursor.execute(sql)
    result = {
        (report_day, comparison_type, comparison_day, scope): (baseline, retained)
        for report_day, comparison_type, comparison_day, scope, baseline, retained, _package_retained in cursor
    }
    if not result or any(baseline <= 0 or retained < 0 or retained > baseline for baseline, retained in result.values()):
        raise RuntimeError("Retention independent controls are incomplete or invalid")
    return result


def serialize_expected(fact: str, expected: dict) -> list[dict[str, object]]:
    if fact == "snapshot":
        return [
            {"key": [report_day.isoformat(), scope], "value": count}
            for (report_day, scope), count in expected.items()
        ]
    return [
        {"key": [report_day.isoformat(), kind, comparison_day.isoformat(), scope], "value": list(value)}
        for (report_day, kind, comparison_day, scope), value in expected.items()
    ]


def deserialize_expected(fact: str, payload: list[dict[str, object]]) -> dict:
    if fact == "snapshot":
        return {
            (date.fromisoformat(entry["key"][0]), entry["key"][1]): int(entry["value"])
            for entry in payload
        }
    return {
        (date.fromisoformat(entry["key"][0]), entry["key"][1], date.fromisoformat(entry["key"][2]), entry["key"][3]):
        (int(entry["value"][0]), int(entry["value"][1]))
        for entry in payload
    }


def source_batch_worker(args: argparse.Namespace) -> None:
    """Run one source control/COPY in an isolated process against one snapshot."""
    start = date.fromisoformat(args.start)
    end = date.fromisoformat(args.end)
    if args.fact == "snapshot":
        extract, controls, expected_for_batch = SNAPSHOT_EXTRACT, SNAPSHOT_CONTROLS, snapshot_expected
    else:
        extract, controls, expected_for_batch = RETENTION_EXTRACT, RETENTION_CONTROLS, retention_expected
    transfer = Path(args.transfer)
    metadata = Path(args.metadata)
    with source_reader(args.snapshot_id) as source:
        with source.cursor() as source_cursor:
            if args.fact == "retention":
                source_cursor.execute("SET LOCAL work_mem = '128MB'")
            if args.fact == "snapshot":
                expected = expected_for_batch(source_cursor, rendered(controls, start, end), start, end)
            else:
                expected = expected_for_batch(source_cursor, rendered(controls, start, end))
        require_batch_space(transfer.parent)
        rows, byte_count, elapsed = copy_source_batch(source, extract, start, end, transfer)
        metadata.write_text(json.dumps({
            "rows": rows,
            "bytes": byte_count,
            "elapsed": elapsed,
            "expected": serialize_expected(args.fact, expected),
        }), encoding="utf-8")
        source.rollback()


def prepare_source_batch(fact: str, snapshot_id: str, start: date, end: date, directory: Path) -> tuple[Path, int | None, int, float, dict]:
    """Bounded isolated source reader; retry only after its process is gone."""
    transfer = directory / f"_{fact}_{start:%Y%m}.copy"
    metadata = directory / f"_{fact}_{start:%Y%m}.json"
    command = [
        sys.executable, str(Path(__file__).resolve()), "--source-batch",
        "--fact", fact, "--start", start.isoformat(), "--end", end.isoformat(),
        "--snapshot-id", snapshot_id, "--transfer", str(transfer), "--metadata", str(metadata),
    ]
    for attempt in range(1, SOURCE_BATCH_MAX_ATTEMPTS + 1):
        transfer.unlink(missing_ok=True)
        metadata.unlink(missing_ok=True)
        try:
            completed = subprocess.run(
                command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                timeout=TRANSPORT_TIMEOUT_SECONDS, check=False,
            )
        except subprocess.TimeoutExpired:
            print(
                f"SOURCE_WORKER_TIMEOUT fact={fact} start={start} attempt={attempt} "
                f"seconds={TRANSPORT_TIMEOUT_SECONDS}", flush=True,
            )
            continue
        if completed.returncode == 0 and metadata.exists() and transfer.exists():
            payload = json.loads(metadata.read_text(encoding="utf-8"))
            expected = deserialize_expected(fact, payload["expected"])
            return transfer, payload["rows"], int(payload["bytes"]), float(payload["elapsed"]), expected
        # The worker has no credentials in its arguments.  Preserve the last
        # diagnostic line so a transport reset can be distinguished from a SQL
        # or filesystem failure without exposing connection settings.
        diagnostic = (completed.stderr or completed.stdout).strip().splitlines()
        reason = diagnostic[-1].strip() if diagnostic else "no_worker_diagnostic"
        print(
            f"SOURCE_WORKER_RETRY fact={fact} start={start} attempt={attempt} "
            f"exit_code={completed.returncode} reason={reason[:500]}",
            flush=True,
        )
        if "UndefinedObject" in reason or "снимок" in reason and "не существует" in reason:
            raise TransportRestartRequired(
                f"Exported source snapshot is invalid fact={fact} start={start}"
            )
        if not source_admission_available():
            raise TransportRestartRequired(
                f"Source admission unavailable after worker failure fact={fact} start={start}"
            )
    raise TransportRestartRequired(f"Source worker exhausted retries fact={fact} start={start}")


def require_snapshot_stage(cursor, start: date, end: date) -> None:
    cursor.execute(
        """
        SELECT count(*) FROM (
          SELECT 1 FROM _client_base_snapshot_stage
          GROUP BY scope_level, report_date, club_id, age_years, age_group, gender,
                   membership_tenure, activity_bucket HAVING count(*) > 1
        ) AS duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Snapshot stage has duplicate contract keys")
    cursor.execute(
        """
        SELECT count(*) FROM _client_base_snapshot_stage
        WHERE report_date < %s OR report_date >= %s
           OR scope_level NOT IN ('club', 'network')
           OR (scope_level = 'club' AND club_id IS NULL)
           OR (scope_level = 'network' AND club_id IS NOT NULL)
           OR client_count <= 0
           OR gender NOT IN ('Женский', 'Мужской', 'Не указано')
           OR membership_tenure NOT IN ('New', 'Renew', 'Ex', 'Не указано')
           OR activity_bucket NOT IN ('Не ходил', '1', '2–3', '4–7', '8+')
           OR NOT (age_group = 'Дети'
                   OR (age_years IS NULL AND age_group = 'Не указано')
                   OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
                   OR (age_years >= 18 AND age_group = 'Взрослые'))
        """, (start, end)
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Snapshot stage violates the fact contract")


def require_retention_stage(cursor, start: date, end: date) -> None:
    cursor.execute(
        """
        SELECT count(*) FROM (
          SELECT 1 FROM _client_base_retention_stage
          GROUP BY scope_level, report_date, comparison_type, comparison_date,
                   baseline_club_id, current_age_years, current_age_group,
                   current_gender, current_membership_tenure HAVING count(*) > 1
        ) AS duplicate_key
        """
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Retention stage has duplicate contract keys")
    cursor.execute(
        """
        SELECT count(*) FROM _client_base_retention_stage
        WHERE report_date < %s OR report_date >= %s
           OR comparison_type NOT IN ('year_start', 'previous_year')
           OR comparison_date > report_date
           OR scope_level NOT IN ('club', 'network')
           OR (scope_level = 'club' AND baseline_club_id IS NULL)
           OR (scope_level = 'network' AND baseline_club_id IS NOT NULL)
           OR baseline_client_count <= 0 OR retained_client_count < 0
           OR retained_client_count > baseline_client_count
           OR current_gender NOT IN ('Женский', 'Мужской', 'Не указано')
           OR current_membership_tenure NOT IN ('New', 'Renew', 'Ex', 'Не указано')
           OR NOT (current_age_group = 'Дети'
                   OR (current_age_years IS NULL AND current_age_group = 'Не указано')
                   OR (current_age_years BETWEEN 14 AND 17 AND current_age_group = 'Юниоры')
                   OR (current_age_years >= 18 AND current_age_group = 'Взрослые'))
        """, (start, end)
    )
    if cursor.fetchone()[0]:
        raise RuntimeError("Retention stage violates the fact contract")


def snapshot_totals(cursor, relation: str) -> dict[tuple[date, str], int]:
    cursor.execute(
        f"SELECT report_date, scope_level, sum(client_count)::bigint FROM {relation} GROUP BY 1, 2"
    )
    return {(day, scope): count for day, scope, count in cursor}


def retention_totals(cursor, relation: str) -> dict[tuple[date, str, date, str], tuple[int, int]]:
    cursor.execute(
        f"""SELECT report_date, comparison_type, comparison_date, scope_level,
                   sum(baseline_client_count)::bigint, sum(retained_client_count)::bigint
            FROM {relation} GROUP BY 1, 2, 3, 4"""
    )
    return {(day, kind, comparison, scope): (baseline, retained)
            for day, kind, comparison, scope, baseline, retained in cursor}


def copy_into_stage(cursor, target, source, extract: Path, controls: Path, stage: str, columns: str,
                    start: date, end: date, directory: Path, expected_for_batch) -> tuple[int, dict]:
    total_rows = 0
    expected_values: dict = {}
    for batch_start, batch_end in month_batches(start, end):
        # The independent aggregate is captured inside the same source snapshot
        # before this batch is copied; it is never derived from the extract.
        with source.cursor() as source_cursor:
            batch_expected = expected_for_batch(
                source_cursor, rendered(controls, batch_start, batch_end), batch_start, batch_end
            )
        if expected_values.keys() & batch_expected.keys():
            raise RuntimeError(f"{stage} independent controls overlap across batches")
        expected_values.update(batch_expected)
        require_batch_space(directory)
        transfer = directory / f"{stage}_{batch_start:%Y%m}.copy"
        try:
            rows, byte_count, elapsed = copy_source_batch(source, extract, batch_start, batch_end, transfer)
            with TransportWatchdog(target, "target_binary_copy"), cursor.copy(f"COPY {stage} ({columns}) FROM STDIN WITH (FORMAT BINARY)") as copied, transfer.open("rb") as input_file:
                while block := input_file.read(1_048_576):
                    copied.write(block)
            if rows is not None and cursor.rowcount != rows:
                raise RuntimeError(f"{stage} COPY count differs: {cursor.rowcount} != {rows}")
            total_rows += cursor.rowcount
            print(f"BATCH_PASS target={stage} start={batch_start} end={batch_end} controls={len(batch_expected)} rows={cursor.rowcount} bytes={byte_count} elapsed_seconds={elapsed:.3f}", flush=True)
        finally:
            transfer.unlink(missing_ok=True)
    return total_rows, expected_values


def copy_single_batch(cursor, target, source, extract: Path, controls: Path, stage: str, columns: str,
                      batch_start: date, batch_end: date, directory: Path, expected_for_batch) -> tuple[int, dict]:
    """Control and transport one fact-month before touching the next fact."""
    with source.cursor() as source_cursor:
        expected = expected_for_batch(source_cursor, rendered(controls, batch_start, batch_end), batch_start, batch_end)
    require_batch_space(directory)
    transfer = directory / f"{stage}_{batch_start:%Y%m}.copy"
    try:
        source_rows, byte_count, elapsed = copy_source_batch(source, extract, batch_start, batch_end, transfer)
        with TransportWatchdog(target, "target_binary_copy"), cursor.copy(f"COPY {stage} ({columns}) FROM STDIN WITH (FORMAT BINARY)") as copied, transfer.open("rb") as input_file:
            while block := input_file.read(1_048_576):
                copied.write(block)
        if source_rows is not None and cursor.rowcount != source_rows:
            raise RuntimeError(f"{stage} COPY count differs: {cursor.rowcount} != {source_rows}")
        print(f"BATCH_PASS target={stage} start={batch_start} end={batch_end} controls={len(expected)} rows={cursor.rowcount} bytes={byte_count} elapsed_seconds={elapsed:.3f}", flush=True)
        return cursor.rowcount, expected
    finally:
        transfer.unlink(missing_ok=True)


def copy_prepared_batch(cursor, target, stage: str, columns: str, transfer: Path,
                        source_rows: int | None, byte_count: int, elapsed: float,
                        start: date, end: date, expected: dict) -> int:
    """Copy a completed isolated source file into target stage exactly once."""
    try:
        with TransportWatchdog(target, "target_binary_copy"), cursor.copy(
            f"COPY {stage} ({columns}) FROM STDIN WITH (FORMAT BINARY)"
        ) as copied, transfer.open("rb") as input_file:
            while block := input_file.read(1_048_576):
                copied.write(block)
        if source_rows is not None and cursor.rowcount != source_rows:
            raise RuntimeError(f"{stage} COPY count differs: {cursor.rowcount} != {source_rows}")
        print(
            f"BATCH_PASS target={stage} start={start} end={end} controls={len(expected)} "
            f"rows={cursor.rowcount} bytes={byte_count} elapsed_seconds={elapsed:.3f}",
            flush=True,
        )
        return cursor.rowcount
    finally:
        transfer.unlink(missing_ok=True)


def require_target_state(cursor, initial: bool) -> None:
    cursor.execute(
        "SELECT to_regclass('mart.client_base_snapshot'), to_regclass('mart.client_base_retention')"
    )
    snapshot, retention = cursor.fetchone()
    if initial and (snapshot is not None or retention is not None):
        raise RuntimeError("Initial load requires both target facts to be absent")
    if not initial and (snapshot is None or retention is None):
        raise RuntimeError("Rerun requires both target facts to exist")


def target_plan(cursor, relation: str, day: date) -> float:
    cursor.execute(
        f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM {relation} "
        "WHERE scope_level = 'network' AND report_date = %s",
        (day,),
    )
    plan = cursor.fetchone()[0][0]
    return float(plan["Execution Time"])


def require_reconciliation(cursor, start: date, end: date, phase: str) -> None:
    cursor.execute(rendered(RECONCILIATION, start, end))
    failures = [(control_id, deviations) for control_id, deviations, _tolerance, status in cursor if status != "PASS"]
    if failures:
        raise RuntimeError(f"Target reconciliation failed phase={phase}: {failures}")
    print(f"TARGET_RECONCILIATION_PASS phase={phase} controls=4", flush=True)


def close_after_failure(endpoint: str, connection) -> None:
    """Release a locally owned session without masking the primary failure."""
    try:
        connection.rollback()
    except Exception as cleanup_error:
        print(f"ROLLBACK_UNAVAILABLE endpoint={endpoint} error={type(cleanup_error).__name__}", flush=True)
    try:
        connection.close()
    except Exception as close_error:
        print(f"CLOSE_UNAVAILABLE endpoint={endpoint} error={type(close_error).__name__}", flush=True)


def run_once(args: argparse.Namespace) -> None:
    start, end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    snapshot_ddl = statements(SNAPSHOT_DDL, start, end)
    retention_ddl = statements(RETENTION_DDL, start, end)
    snapshot_replace = statements(SNAPSHOT_REPLACE, start, end)
    retention_replace = statements(RETENTION_REPLACE, start, end)
    if (len(snapshot_ddl), len(retention_ddl), len(snapshot_replace), len(retention_replace)) != (2, 2, 2, 2):
        raise RuntimeError("Reviewed SQL statement count changed")

    started_at = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="client_base_snapshot_retention_") as temporary_directory:
        directory = Path(temporary_directory)
        prepared_batches: list[tuple[str, Path, int | None, int, float, date, date, dict]] = []
        transport_preflight("source")
        source_owner = connect_source_with_retry("client_base_snapshot_retention_source_owner")
        try:
            with source_owner.cursor() as source_cursor:
                source_cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
                source_cursor.execute("SELECT pg_export_snapshot()")
                snapshot_id = source_cursor.fetchone()[0]
            print(
                f"SOURCE_SNAPSHOT horizon={start}..{end} control_mode=monthly_before_copy "
                f"reader_lifecycle=reconnect_per_fact_month target_lifecycle=connect_after_source_stage "
                f"source_driver=psycopg2-{psycopg2.__version__.split()[0]} "
                f"target_driver=psycopg-{psycopg.__version__}",
                flush=True,
            )
            # Do not hold a target transaction or advisory lock while VPN-backed
            # source extraction runs.  Every file is still based on this one
            # exported snapshot; the target phase below remains fully atomic.
            for batch_start, batch_end in month_batches(start, end):
                for fact in ("snapshot", "retention"):
                    transfer, source_rows, byte_count, elapsed, expected = prepare_source_batch(
                        fact, snapshot_id, batch_start, batch_end, directory
                    )
                    prepared_batches.append(
                        (fact, transfer, source_rows, byte_count, elapsed, batch_start, batch_end, expected)
                    )
                    print(
                        f"SOURCE_STAGE_PASS fact={fact} start={batch_start} end={batch_end} "
                        f"controls={len(expected)} rows={source_rows} bytes={byte_count} "
                        f"elapsed_seconds={elapsed:.3f}",
                        flush=True,
                    )
            source_owner.rollback()
            source_owner.close()
        except Exception:
            close_after_failure("source_owner", source_owner)
            raise

        transport_preflight("mart")
        target = connect_with_retry(
            lambda: psycopg.connect(**mart_config("client_base_snapshot_retention_target")), endpoint="mart"
        )
        try:
            with target.cursor() as target_cursor:
                target_cursor.execute("BEGIN")
                target_cursor.execute("SET LOCAL lock_timeout = '60s'")
                target_cursor.execute("SET LOCAL idle_in_transaction_session_timeout = '240s'")
                target_cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ("mart.client_base_snapshot_retention:refresh",))
                require_target_state(target_cursor, args.initial_load)
                if args.initial_load:
                    for statement in snapshot_ddl + retention_ddl:
                        target_cursor.execute(statement)
                target_cursor.execute("CREATE TEMP TABLE _client_base_snapshot_stage (LIKE mart.client_base_snapshot INCLUDING DEFAULTS) ON COMMIT DROP")
                target_cursor.execute("CREATE TEMP TABLE _client_base_retention_stage (LIKE mart.client_base_retention INCLUDING DEFAULTS) ON COMMIT DROP")
                snapshot_rows = retention_rows = 0
                snapshot_expected_values: dict = {}
                retention_expected_values: dict = {}
                for fact, transfer, source_rows, byte_count, elapsed, batch_start, batch_end, expected in prepared_batches:
                    if fact == "snapshot":
                        stage, columns, expected_values = (
                            "_client_base_snapshot_stage", SNAPSHOT_COLUMNS, snapshot_expected_values
                        )
                    else:
                        stage, columns, expected_values = (
                            "_client_base_retention_stage", RETENTION_COLUMNS, retention_expected_values
                        )
                    rows = copy_prepared_batch(
                        target_cursor, target, stage, columns, transfer, source_rows, byte_count,
                        elapsed, batch_start, batch_end, expected,
                    )
                    if expected_values.keys() & expected.keys():
                        raise RuntimeError(f"{fact.title()} independent controls overlap across batches")
                    expected_values.update(expected)
                    if fact == "snapshot":
                        snapshot_rows += rows
                    else:
                        retention_rows += rows
                require_snapshot_stage(target_cursor, start, end)
                require_retention_stage(target_cursor, start, end)
                if snapshot_totals(target_cursor, "_client_base_snapshot_stage") != snapshot_expected_values:
                    raise RuntimeError("Snapshot stage differs from independent source controls")
                if retention_totals(target_cursor, "_client_base_retention_stage") != retention_expected_values:
                    raise RuntimeError("Retention stage differs from independent source controls")
                for statement in snapshot_replace + retention_replace:
                    target_cursor.execute(statement)
                if snapshot_totals(target_cursor, "mart.client_base_snapshot") != snapshot_expected_values:
                    raise RuntimeError("Snapshot target differs from its source snapshot")
                if retention_totals(target_cursor, "mart.client_base_retention") != retention_expected_values:
                    raise RuntimeError("Retention target differs from its source snapshot")
                require_reconciliation(target_cursor, start, end, "pre_commit")
                target.commit()
            print(f"TARGET_COMMIT snapshot_rows={snapshot_rows} retention_rows={retention_rows} elapsed_seconds={time.monotonic() - started_at:.3f}", flush=True)
            with target.cursor() as target_cursor:
                require_reconciliation(target_cursor, start, end, "post_commit")
                snapshot_plan_ms = target_plan(target_cursor, "mart.client_base_snapshot", start)
                retention_plan_ms = target_plan(target_cursor, "mart.client_base_retention", start)
            print(f"TARGET_READ_PLAN snapshot_ms={snapshot_plan_ms:.3f} retention_ms={retention_plan_ms:.3f}", flush=True)
            target.close()
        except Exception:
            close_after_failure("target", target)
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--initial-load", action="store_true", help="create both absent facts and load them atomically")
    mode.add_argument("--rerun", action="store_true", help="atomically replace both existing facts from a new source snapshot")
    parser.add_argument("--source-batch", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--fact", choices=("snapshot", "retention"), help=argparse.SUPPRESS)
    parser.add_argument("--start", help=argparse.SUPPRESS)
    parser.add_argument("--end", help=argparse.SUPPRESS)
    parser.add_argument("--snapshot-id", help=argparse.SUPPRESS)
    parser.add_argument("--transfer", help=argparse.SUPPRESS)
    parser.add_argument("--metadata", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.source_batch:
        required = ("fact", "start", "end", "snapshot_id", "transfer", "metadata")
        if any(getattr(args, name) is None for name in required):
            parser.error("--source-batch requires fact, dates, snapshot and file paths")
        source_batch_worker(args)
        return
    if not args.initial_load and not args.rerun:
        parser.error("one of --initial-load or --rerun is required")

    try:
        run_once(args)
    except (
        TransportRestartRequired,
        psycopg.OperationalError,
        psycopg.InterfaceError,
        psycopg2.OperationalError,
        psycopg2.InterfaceError,
    ) as error:
        print(
            f"RERUN_TRANSPORT_FAILURE error={type(error).__name__} "
            "automatic_full_restart=disabled",
            flush=True,
        )
        raise


if __name__ == "__main__":
    main()
