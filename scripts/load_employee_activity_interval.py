#!/usr/bin/env python3
"""Atomically rebuild mart.employee_activity_interval from reviewed 1C SQL."""
from __future__ import annotations
import argparse, re, shutil, sys, tempfile, time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
from scripts.load_children_package_sale import br003_horizon, config

EXTRACT = ROOT / 'sql/marts/employee_activity_interval_extract.sql'
CONTROLS = ROOT / 'sql/marts/employee_activity_interval_source_controls.sql'
DDL = ROOT / 'sql/marts/employee_activity_interval_ddl.sql'
RECON = ROOT / 'sql/tests/employee_activity_interval_reconciliation.sql'
TABLE, STAGE, TIMEOUT = 'mart.employee_activity_interval', '_employee_activity_interval_stage', 180
COLUMNS = ('activity_event_key, activity_date, club_id, employee_id, activity_id, service_id, '
           'room_id, activity_kind, start_at, end_at, duration_minutes, payment_kind')

def statements(path: Path) -> list[str]:
    body = '\n'.join(x for x in path.read_text(encoding='utf-8').splitlines() if not x.lstrip().startswith('--'))
    return [x.strip() for x in body.split(';') if x.strip()]

def render(path: Path, start: date, end: date) -> str:
    text = path.read_text(encoding='utf-8').strip().rstrip(';')
    return text.replace('$2::date', f"DATE '{end.isoformat()}'").replace('$1::date', f"DATE '{start.isoformat()}'")

def run_control(cur, marker: str, start: date, end: date) -> dict[str, object]:
    stmt = next(x for x in statements(CONTROLS) if marker in x)
    values = (start, end)
    args = tuple(values[int(m.group(1)) - 1] for m in re.finditer(r'\$(\d+)::date', stmt))
    cur.execute(re.sub(r'\$\d+::date', '%s', stmt), args)
    row = cur.fetchone()
    if row is None: raise RuntimeError(f'{marker} returned no row')
    return dict(zip([x.name for x in cur.description], row, strict=True))

def expected(cur, start: date, end: date) -> dict[str, object]:
    lesson, duty, coupon = (run_control(cur, x, start, end) for x in ('EW-S3-LESSON', 'EW-S3-DUTY', 'EW-V03B'))
    if any(int(x) for x in (coupon['collapsed_keys_with_divergent_coupon_minutes'], coupon['collapsed_keys_with_divergent_visit_day'], coupon['collapsed_keys_with_divergent_dimension_ids'], coupon['nonpositive_or_null_coupon_minutes_rows'])):
        raise RuntimeError('Coupon expected control is not deterministic for target fields')
    minima = [x for x in (lesson['lesson_min_date'], duty['duty_min_date']) if x is not None]
    maxima = [x for x in (lesson['lesson_max_date'], duty['duty_max_date']) if x is not None]
    return {'rows': int(lesson['pz_target_rows']) + int(lesson['gz_target_rows']) + int(duty['duty_target_rows']) + int(coupon['current_m_distinct_rows']),
            'training_rows': int(lesson['pz_target_rows']) + int(lesson['gz_target_rows']), 'duty_rows': int(duty['duty_target_rows']),
            'coupon_rows': int(coupon['current_m_distinct_rows']), 'training_minutes': lesson['pz_target_minutes'] + lesson['gz_target_minutes'],
            'duty_minutes': duty['clean_duty_minutes'], 'coupon_minutes': coupon['current_m_distinct_coupon_minutes'],
            'min_date': min(minima), 'max_date': max(maxima), 'distinct_keys': int(lesson['pz_target_rows']) + int(lesson['gz_target_rows']) + int(duty['duty_target_rows']) + int(coupon['current_m_distinct_rows'])}

def reconcile(cur, exp: dict[str, object], start: date, end: date) -> None:
    body = RECON.read_text(encoding='utf-8')
    values = (exp['rows'], exp['training_rows'], exp['duty_rows'], exp['coupon_rows'], exp['training_minutes'], exp['duty_minutes'], exp['coupon_minutes'], exp['min_date'], exp['max_date'], exp['distinct_keys'], start, end)
    args = tuple(values[int(m.group(1)) - 1] for m in re.finditer(r'\$(\d+)', body))
    cur.execute(re.sub(r'\$\d+', '%s', body), args)
    failed = [r[:3] for r in cur.fetchall() if r[4] != 'PASS']
    if failed: raise RuntimeError(f'target reconciliation failed: {failed}')

def close(conn) -> None:
    if conn:
        try: conn.rollback()
        except Exception: pass
        try: conn.close()
        except Exception: pass

def run(initial: bool) -> None:
    start, end = br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
    if shutil.disk_usage('/tmp').free < 1_073_741_824: raise RuntimeError('Less than 1 GiB for the sole COPY buffer')
    source = target = None
    with tempfile.TemporaryDirectory(prefix='employee_activity_interval_') as directory:
      transfer = Path(directory) / 'employee_activity_interval.copy'
      try:
        source = connect_with_retry(lambda: psycopg.connect(**config('SOURCE_')), endpoint='source')
        with source.cursor() as cur:
            cur.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            cur.execute(f"SET LOCAL statement_timeout = '{TIMEOUT}s'")
            exp = expected(cur, start, end)
            with transfer.open('wb') as out, cur.copy(f'COPY ({render(EXTRACT, start, end)}) TO STDOUT WITH (FORMAT BINARY)') as copied:
                for block in copied: out.write(block)
            if cur.rowcount != exp['rows']: raise RuntimeError(f"source COPY rows {cur.rowcount} != expected {exp['rows']}")
        target = connect_with_retry(lambda: psycopg.connect(**config('MART_')), endpoint='mart')
        with target.cursor() as cur:
            cur.execute('BEGIN'); cur.execute("SET LOCAL lock_timeout = '60s'"); cur.execute(f"SET LOCAL statement_timeout = '{TIMEOUT}s'")
            cur.execute('SELECT pg_advisory_xact_lock(hashtext(%s))', ('mart.employee_activity_interval:refresh',))
            cur.execute('SELECT to_regclass(%s)', (TABLE,)); exists = cur.fetchone()[0] is not None
            if initial == exists: raise RuntimeError('Initial/rerun target state does not match requested operation')
            if initial:
                for stmt in statements(DDL): cur.execute(stmt)
            cur.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TABLE} INCLUDING DEFAULTS) ON COMMIT DROP')
            with transfer.open('rb') as inp, cur.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as copied:
                while block := inp.read(1_048_576): copied.write(block)
            if cur.rowcount != exp['rows']: raise RuntimeError('target COPY row count differs')
            cur.execute(f'DELETE FROM {TABLE}'); cur.execute(f'INSERT INTO {TABLE} ({COLUMNS}) SELECT {COLUMNS} FROM {STAGE}')
            reconcile(cur, exp, start, end); target.commit()
        with target.cursor() as cur:
            cur.execute(f'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT activity_date, club_id, employee_id, duration_minutes FROM {TABLE} WHERE activity_date >= %s AND activity_date < %s', (start, end))
            plan = cur.fetchone()[0][0]; print(f"TARGET_READ_PLAN execution_ms={plan['Execution Time']:.3f} rows={plan['Plan'].get('Actual Rows')}")
      except Exception:
        close(target); raise
      finally:
        close(source)
        if target: target.close()

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('--initial', action='store_true'); p.add_argument('--rerun', action='store_true'); a=p.parse_args()
    if a.initial == a.rerun: raise SystemExit('Specify exactly one of --initial or --rerun')
    run(a.initial)
if __name__ == '__main__': main()
