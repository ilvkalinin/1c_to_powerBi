#!/usr/bin/env python3
"""Build the approved compact CRM facts from a read-only 1C snapshot."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
from psycopg import sql as pg_sql


ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "sql/marts/crm_br032_source_extract.sql"
DDL_PLAN = ROOT / "sql/marts/crm_br032_reviewed_plan.sql"
CORE_CREATED_WINDOW_GUARD = ROOT / "sql/tests/crm_br032_quarter_created_window.sql"

OBJECTS = (
    "crm_interaction",
    "crm_interaction_phone",
    "feedback_interaction",
    "club_day_metrics",
    "v_sales_interaction",
    "v_feedback_interaction",
    "v_guest_tour",
)
OLD_OBJECTS = (
    "crm_interaction",
    "crm_interaction_phone",
    "crm_interaction_comment",
    "v_sales_interaction",
    "v_feedback_interaction",
    "v_guest_tour",
)
COLUMNS = {
    "core": """interaction_id, task_id, task_code, created_at, started_at, ended_at,
        planned_at, interaction_name, event_type_id, event_type_name, state_id,
        state_name, status_id, status_name, executor_id, executor_name,
        cancellation_reason_name, client_id, client_code, client_name, client_phone,
        club_id, club_name, network_name, funnel_id, funnel_name, campaign_id,
        campaign_name, channel_id, tenure_type_name, client_status_name, sales_scope,
        guest_scope, report_date, tour_kind""",
    "phone": "interaction_id, phone_reference_id, phone_event_id, phone_at, answered_flag",
    "feedback": """task_code, task_description, interaction_name, created_at, started_at,
        ended_at, planned_at, feedback_topic_name, feedback_theme, club_name,
        funnel_name, department_name, status_name, state_name, executor_name,
        position_name, client_code, client_name, client_phone, tenure_type_name,
        campaign_name, campaign_code, channel_name, regulated_interaction_name,
        cancellation_reason_name, comment_text, comment_updated_at, first_followup_at,
        answered_flag, worked_at, worked_flag, response_minutes, resolution_days""",
    "club_day": "event_date, club_id, club_name, visit_event_count",
}
TARGETS = {
    "core": "mart.crm_interaction",
    "phone": "mart.crm_interaction_phone",
    "feedback": "mart.feedback_interaction",
    "club_day": "mart.club_day_metrics",
}
CONNECT_ATTEMPTS = 5
CONNECT_RETRY_INTERVAL_SECONDS = 15
TARGET_TRANSACTION_ATTEMPTS = 5
TARGET_COPY_TIMEOUT_MILLISECONDS = 300_000
CREATED_WINDOW_LOOKBACK = timedelta(days=71)
CREATED_WINDOW_LOOKAHEAD = timedelta(days=1)


def config(prefix: str, application_name: str | None = None) -> dict[str, str | int]:
    names = ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
    values = {name: os.environ.get(prefix + name) for name in names}
    missing = [prefix + name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing configuration: " + ", ".join(missing))
    result = {
        "host": values["PGHOST"], "port": values["PGPORT"],
        "dbname": values["PGDATABASE"], "user": values["PGUSER"],
        "password": values["PGPASSWORD"],
        # Make this loader distinguishable from other clients sharing the
        # technical account, and bound failures while opening a new session.
        "application_name": application_name or (
            "crm_br032_source_loader" if prefix == "SOURCE_"
            else "crm_br032_mart_loader"
        ),
        "connect_timeout": 15,
    }
    sslmode = os.environ.get(prefix + "PGSSLMODE")
    if sslmode:
        result["sslmode"] = sslmode
    return result


def connect_with_retry(prefix: str, application_name: str | None = None) -> psycopg.Connection:
    """Open a database session with bounded retries for transient admission failures.

    Attempts start 15 seconds apart.  Each attempt has the same 15-second
    PostgreSQL connection timeout, so an unavailable host can delay this
    loader by at most 75 seconds before the original connection error is
    surfaced.  SQL errors and authentication failures are intentionally not
    retried: reconnecting cannot make either condition valid.
    """
    first_attempt_started = time.monotonic()
    last_error: psycopg.OperationalError | None = None
    role = "source" if prefix == "SOURCE_" else "target"
    for attempt in range(1, CONNECT_ATTEMPTS + 1):
        scheduled_start = first_attempt_started + (attempt - 1) * CONNECT_RETRY_INTERVAL_SECONDS
        if (delay := scheduled_start - time.monotonic()) > 0:
            time.sleep(delay)
        try:
            connection = psycopg.connect(**config(prefix, application_name))
        except psycopg.OperationalError as error:
            # Authentication, role, and database selection failures are stable
            # configuration errors, unlike a lost or delayed TCP admission.
            if error.sqlstate and error.sqlstate.startswith(("28", "3D")):
                raise
            last_error = error
            print(
                f"CONNECT_RETRY role={role} attempt={attempt}/{CONNECT_ATTEMPTS} "
                "status=connection_failed",
                file=sys.stderr,
                flush=True,
            )
        else:
            if attempt > 1:
                print(
                    f"CONNECT_RESTORED role={role} attempt={attempt}/{CONNECT_ATTEMPTS}",
                    flush=True,
                )
            return connection
    assert last_error is not None
    raise last_error


def br003_horizon(today: date) -> tuple[date, date]:
    years_back = 2 if today.month <= 3 else 1
    # CRM initial load is historical-to-current only: it must not transfer
    # planned future interaction rows merely because the generic BR-003 upper
    # boundary is next 1 January.
    return date(today.year - years_back, 1, 1), today


def next_chunk(start: date, limit: date, months: int) -> date:
    month = start.month + months
    year = start.year + (month - 1) // 12
    month = (month - 1) % 12 + 1
    return min(date(year, month, 1), limit)


def sql_sections() -> dict[str, str]:
    text = EXTRACT.read_text(encoding="utf-8")
    parts = re.split(r"(?m)^-- name: ([a-z_]+)\n", text)
    sections = {parts[index]: parts[index + 1].strip().rstrip(";")
                for index in range(1, len(parts), 2)}
    required = set(TARGETS)
    if set(sections) != required:
        raise RuntimeError(f"Unexpected source-query names: {sorted(sections)}")
    return sections


def render(query: str, start: date, end: date,
           chunk_start: date | None = None, chunk_end: date | None = None) -> str:
    values: dict[str, date] = {"1": start, "2": end}
    if chunk_start is not None and chunk_end is not None:
        values.update({"3": chunk_start, "4": chunk_end})
    for number, value in values.items():
        query = query.replace(
            f"${number}::timestamp without time zone",
            f"TIMESTAMP '{value.isoformat()}'",
        ).replace(f"${number}::date", f"DATE '{value.isoformat()}'")
    if re.search(r"\$[1-9]", query):
        raise RuntimeError("Unrendered source-query placeholder")
    return query


def ddl_without_transaction() -> str:
    text = DDL_PLAN.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^BEGIN;\s*", "", text, count=1)
    text = re.sub(r"(?m)^COMMIT;\s*$", "", text, count=1)
    if "CREATE TABLE mart.crm_interaction" not in text or "DROP TABLE mart.crm_interaction" not in text:
        raise RuntimeError("Unexpected DDL plan")
    return text


def verify_old_empty(cursor) -> None:
    cursor.execute(
        """
        SELECT relname
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'mart' AND relname = ANY(%s)
        """,
        (list(OLD_OBJECTS),),
    )
    found = {row[0] for row in cursor}
    if found != set(OLD_OBJECTS):
        raise RuntimeError("The approved empty CRM replacement targets do not match VM-2")
    for relation in ("mart.crm_interaction", "mart.crm_interaction_phone", "mart.crm_interaction_comment"):
        cursor.execute(f"SELECT count(*) FROM {relation}")
        if cursor.fetchone()[0] != 0:
            raise RuntimeError("Approved replacement target is not empty")


def verify_new_objects(cursor) -> None:
    cursor.execute(
        """
        SELECT relname
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'mart' AND relname = ANY(%s)
        """,
        (list(OBJECTS),),
    )
    if {row[0] for row in cursor} != set(OBJECTS):
        raise RuntimeError("Compact CRM target objects are not complete")


def source_copy_to_file(source_cursor, name: str, query: str, directory: Path, ordinal: int) -> tuple[Path, int]:
    copy_out = f"COPY ({query}) TO STDOUT WITH (FORMAT BINARY)"
    transfer_path = directory / f"{ordinal:03d}_{name}.copy"
    with transfer_path.open("wb") as transfer, source_cursor.copy(copy_out) as from_source:
        while block := from_source.read():
            transfer.write(block)
    rows = source_cursor.rowcount
    print(f"SOURCE_COPY_READY name={name} rows={rows} bytes={transfer_path.stat().st_size}", flush=True)
    return transfer_path, rows


def source_copy_from_snapshot(snapshot_id: str, name: str, query: str,
                              directory: Path, ordinal: int) -> tuple[Path, int]:
    """Copy one bounded transport chunk from the shared read-only snapshot."""
    with connect_with_retry("SOURCE_", "crm_br032_source_chunk_loader") as source:
        source.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY").close()
        # Import must be the first statement after BEGIN in this transaction.
        source.execute(
            pg_sql.SQL("SET TRANSACTION SNAPSHOT {}").format(pg_sql.Literal(snapshot_id))
        ).close()
        source.execute("SET LOCAL statement_timeout = '300000'").close()
        with source.cursor() as copy_cursor:
            path, rows = source_copy_to_file(copy_cursor, name, query, directory, ordinal)
        source.rollback()
    return path, rows


def target_copy_from_file(target_cursor, name: str, transfer_path: Path, expected_rows: int) -> None:
    columns = " ".join(COLUMNS[name].split())
    copy_in = f"COPY {TARGETS[name]} ({columns}) FROM STDIN WITH (FORMAT BINARY)"
    # A stalled socket must abort this one statement, not leave an open target
    # transaction indefinitely. The caller then retries the whole atomic load.
    target_cursor.execute(
        f"SET LOCAL statement_timeout = '{TARGET_COPY_TIMEOUT_MILLISECONDS}'"
    )
    with target_cursor.copy(copy_in) as to_target, transfer_path.open("rb") as transfer_input:
        while block := transfer_input.read(1_048_576):
            to_target.write(block)
    if target_cursor.rowcount != expected_rows:
        raise RuntimeError(f"COPY row count mismatch for {name}")


def target_counts(cursor) -> dict[str, int]:
    result: dict[str, int] = {}
    for name, relation in TARGETS.items():
        cursor.execute(f"SELECT count(*)::bigint FROM {relation}")
        result[name] = cursor.fetchone()[0]
    return result


def reconciliation(cursor, expected: dict[str, int]) -> None:
    actual = target_counts(cursor)
    if actual != expected:
        raise RuntimeError(f"Target counts do not equal source COPY totals: {actual}")
    checks = {
        "duplicate_core": "SELECT count(*) FROM (SELECT interaction_id FROM mart.crm_interaction GROUP BY 1 HAVING count(*) > 1) q",
        "duplicate_phone": "SELECT count(*) FROM (SELECT interaction_id, phone_reference_id, phone_event_id FROM mart.crm_interaction_phone GROUP BY 1,2,3 HAVING count(*) > 1) q",
        "duplicate_club_day": "SELECT count(*) FROM (SELECT event_date, club_id FROM mart.club_day_metrics GROUP BY 1,2 HAVING count(*) > 1) q",
        "invalid_core": "SELECT count(*) FROM mart.crm_interaction WHERE interaction_id IS NULL OR task_id IS NULL OR created_at IS NULL OR NOT (sales_scope OR guest_scope)",
        "invalid_feedback": "SELECT count(*) FROM mart.feedback_interaction WHERE worked_flag <> (worked_at IS NOT NULL) OR (response_minutes IS NOT NULL AND worked_at IS NULL)",
        "public_select": """SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
            WHERE n.nspname='mart' AND c.relname = ANY(%s)
              AND a.grantee=0 AND a.privilege_type='SELECT'""",
    }
    for name, statement in checks.items():
        cursor.execute(statement, (list(OBJECTS),) if name == "public_select" else None)
        if cursor.fetchone()[0] != 0:
            raise RuntimeError(f"Reconciliation failed: {name}")


def assert_core_created_window(cursor, start: date, end: date) -> None:
    """Stop before transport when the observed created_at window no longer holds.

    CORE-001 filters each chunk by created_at for performance.  This query
    independently reproduces the unfiltered CORE-001 membership in the same
    read-only snapshot, so a newly late-entered interaction cannot be omitted
    silently by that transport-only predicate.
    """
    query = render(CORE_CREATED_WINDOW_GUARD.read_text(encoding="utf-8"), start, end)
    cursor.execute("SET LOCAL statement_timeout = '180000'")
    cursor.execute("SHOW statement_timeout")
    timeout = cursor.fetchone()[0]
    if timeout != "3min":
        raise RuntimeError(f"Unexpected core created-window guard timeout: {timeout}")
    print("CORE_CREATED_WINDOW_GUARD_START timeout_seconds=180", flush=True)
    cursor.execute(query)
    breaches: list[str] = []
    total_rows = 0
    for row in cursor.fetchall():
        (quarter, interaction_count, _earliest_created, _latest_created,
         _earliest_anchor, _latest_anchor, required_lookback,
         required_lookahead, _outside_one_month, _outside_quarter,
         null_created_at_count, _sales_count, _guest_count) = row
        total_rows += interaction_count
        if null_created_at_count:
            breaches.append(f"{quarter}:null_created_at={null_created_at_count}")
        if required_lookback is not None and required_lookback > CREATED_WINDOW_LOOKBACK:
            breaches.append(f"{quarter}:lookback={required_lookback}")
        # The source predicate is exclusive at chunk_end + 1 day.
        if required_lookahead is not None and required_lookahead >= CREATED_WINDOW_LOOKAHEAD:
            breaches.append(f"{quarter}:lookahead={required_lookahead}")
    if breaches:
        raise RuntimeError(
            "CORE_CREATED_WINDOW_GUARD_FAILED " + "; ".join(breaches)
        )
    print(
        "CORE_CREATED_WINDOW_GUARD_OK "
        f"rows={total_rows} lookback_days={CREATED_WINDOW_LOOKBACK.days} "
        f"lookahead_days={CREATED_WINDOW_LOOKAHEAD.days}",
        flush=True,
    )


def validate_source(sections: dict[str, str], start: date, end: date, chunk_months: int) -> None:
    chunk_end = next_chunk(start, end, chunk_months)
    plans = (
        ("core", render(sections["core"], start, end, start, chunk_end)),
        ("phone", render(sections["phone"], start, end, start, chunk_end)),
        ("feedback", render(sections["feedback"], start, end, start, chunk_end)),
        ("club_day", render(sections["club_day"], start, end)),
        ("core_created_window_guard", render(
            CORE_CREATED_WINDOW_GUARD.read_text(encoding="utf-8"), start, end
        )),
    )
    with connect_with_retry("SOURCE_") as source:
        with source.cursor() as cursor:
            cursor.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            cursor.execute("SET LOCAL statement_timeout = '120000'")
            for name, query in plans:
                cursor.execute(f"EXPLAIN (FORMAT JSON) {query}")
                cursor.fetchone()
                print(f"SOURCE_SQL_VALID name={name}", flush=True)
            source.rollback()


def load_manifest_to_target(mode: str, manifest: list[tuple[str, str, Path, int]],
                            expected: dict[str, int]) -> None:
    """Load prepared source files in one target transaction, with bounded retry.

    A connection loss or target COPY timeout rolls back the entire attempt.
    Prepared files remain local, so retrying VM-2 never re-queries VM-1.
    """
    retryable = (psycopg.OperationalError, psycopg.errors.QueryCanceled)
    for attempt in range(1, TARGET_TRANSACTION_ATTEMPTS + 1):
        try:
            with connect_with_retry("MART_") as target:
                with target.cursor() as target_cursor:
                    print(
                        f"TARGET_TRANSACTION_START attempt={attempt}/{TARGET_TRANSACTION_ATTEMPTS}",
                        flush=True,
                    )
                    target_cursor.execute("BEGIN")
                    target_cursor.execute(
                        "SELECT pg_advisory_xact_lock(hashtext(%s))",
                        ("mart.crm_br032:refresh",),
                    )
                    if mode == "apply":
                        target_cursor.execute(ddl_without_transaction())
                    else:
                        verify_new_objects(target_cursor)
                        target_cursor.execute(
                            "TRUNCATE mart.crm_interaction_phone, mart.crm_interaction, "
                            "mart.feedback_interaction, mart.club_day_metrics"
                        )
                    for name, label, path, rows in manifest:
                        print(
                            f"TARGET_COPY_START name={name} chunk={label} rows={rows} "
                            f"timeout_seconds={TARGET_COPY_TIMEOUT_MILLISECONDS // 1000}",
                            flush=True,
                        )
                        target_copy_from_file(target_cursor, name, path, rows)
                        print(f"TARGET_COPY name={name} chunk={label} rows={rows}", flush=True)
                    reconciliation(target_cursor, expected)
                    target.commit()
            return
        except retryable as error:
            if attempt == TARGET_TRANSACTION_ATTEMPTS:
                raise
            print(
                f"TARGET_TRANSACTION_RETRY attempt={attempt}/{TARGET_TRANSACTION_ATTEMPTS} "
                f"error={type(error).__name__} delay_seconds={CONNECT_RETRY_INTERVAL_SECONDS}",
                file=sys.stderr,
                flush=True,
            )
            time.sleep(CONNECT_RETRY_INTERVAL_SECONDS)


def rebuild(mode: str, sections: dict[str, str], start: date, end: date, chunk_months: int) -> None:
    expected = {name: 0 for name in TARGETS}
    begun = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="crm_br032_") as temp_directory:
        transfer_directory = Path(temp_directory)
        manifest: list[tuple[str, str, Path, int]] = []
        with connect_with_retry("SOURCE_", "crm_br032_source_snapshot_owner") as snapshot_owner:
            snapshot_owner.execute("BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY").close()
            with snapshot_owner.cursor() as cursor:
                cursor.execute("SELECT pg_export_snapshot()")
                snapshot_id = cursor.fetchone()[0]
            print("SOURCE_SNAPSHOT_EXPORTED", flush=True)
            with snapshot_owner.cursor() as guard_cursor:
                assert_core_created_window(guard_cursor, start, end)
            ordinal = 0
            for name in ("core", "phone", "feedback"):
                chunk_start = start
                while chunk_start < end:
                    chunk_end = next_chunk(chunk_start, end, chunk_months)
                    path, rows = source_copy_from_snapshot(snapshot_id, name, render(
                        sections[name], start, end, chunk_start, chunk_end
                    ), transfer_directory, ordinal)
                    manifest.append((name, f"{chunk_start}..{chunk_end}", path, rows))
                    expected[name] += rows
                    ordinal += 1
                    chunk_start = chunk_end
            chunk_start = start
            while chunk_start < end:
                chunk_end = next_chunk(chunk_start, end, chunk_months)
                path, rows = source_copy_from_snapshot(snapshot_id, "club_day", render(
                    sections["club_day"], chunk_start, chunk_end
                ), transfer_directory, ordinal)
                manifest.append(("club_day", f"{chunk_start}..{chunk_end}", path, rows))
                expected["club_day"] += rows
                ordinal += 1
                chunk_start = chunk_end
            snapshot_owner.rollback()

        load_manifest_to_target(mode, manifest, expected)
    print(f"DML_COMMITTED mode={mode} horizon={start}..{end} rows={expected} elapsed_seconds={time.monotonic()-begun:.3f}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--validate-source", action="store_true", help="read-only source SQL validation")
    action.add_argument("--apply", action="store_true", help="approved replacement DDL plus initial full rebuild")
    action.add_argument("--rebuild", action="store_true", help="approved compact-fact rerun without DDL")
    parser.add_argument("--start", type=date.fromisoformat)
    parser.add_argument("--end", type=date.fromisoformat)
    parser.add_argument("--chunk-months", type=int, default=3)
    args = parser.parse_args()
    default_start, default_end = br003_horizon(datetime.now(ZoneInfo("Europe/Moscow")).date())
    start, end = args.start or default_start, args.end or default_end
    if start >= end:
        raise SystemExit("--start must be earlier than --end")
    if not 1 <= args.chunk_months <= 12:
        raise SystemExit("--chunk-months must be between 1 and 12")
    sections = sql_sections()
    if args.validate_source:
        validate_source(sections, start, end, args.chunk_months)
        return
    if args.apply:
        with connect_with_retry("MART_") as target:
            with target.cursor() as cursor:
                verify_old_empty(cursor)
                target.rollback()
        rebuild("apply", sections, start, end, args.chunk_months)
    else:
        rebuild("rebuild", sections, start, end, args.chunk_months)


if __name__ == "__main__":
    try:
        main()
    except psycopg.Error as error:
        diagnostic = error.diag
        parts = [type(error).__name__]
        if diagnostic.sqlstate:
            parts.append(f"sqlstate={diagnostic.sqlstate}")
        if diagnostic.table_name:
            parts.append(f"table={diagnostic.table_name}")
        if diagnostic.column_name:
            parts.append(f"column={diagnostic.column_name}")
        if diagnostic.message_primary:
            parts.append(f"reason={diagnostic.message_primary}")
        print("CRM_LOAD_FAILED " + " ".join(parts), file=sys.stderr, flush=True)
        raise SystemExit(1)
