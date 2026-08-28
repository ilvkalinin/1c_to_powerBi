#!/usr/bin/env python3
"""Plan or atomically load BR-045 employee presence from the read-only 1C source."""
from __future__ import annotations

import argparse, os, re, shutil, sys, tempfile, time
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.mart_connection import connect_with_retry
from scripts.load_children_package_sale import br003_horizon

EXTRACT = ROOT / 'sql/marts/employee_presence_day_br045_extract.sql'
CONTROLS = ROOT / 'sql/marts/employee_presence_day_br045_source_controls.sql'
DDL = ROOT / 'sql/marts/employee_presence_day_br045_ddl.sql'
RECON = ROOT / 'sql/tests/employee_presence_day_br045_reconciliation.sql'
TARGET, STAGE = 'mart.employee_presence_day', '_employee_presence_day_stage'
COLUMNS = 'presence_date, club_id, employee_id, presence_minutes'
TIMEOUT = 600
SOURCE_WORK_MEM = '128MB'

def config(prefix: str) -> dict[str, str]:
    names = ('PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD')
    values = {n: os.environ.get(prefix + n) for n in names}
    if missing := [prefix + n for n, v in values.items() if not v]:
        raise RuntimeError(f'Missing configuration: {", ".join(missing)}')
    return {'host': values['PGHOST'], 'port': values['PGPORT'], 'dbname': values['PGDATABASE'], 'user': values['PGUSER'], 'password': values['PGPASSWORD']}

def open_db(prefix: str, name: str):
    return connect_with_retry(lambda: psycopg.connect(**(config(prefix) | {'application_name': name, 'connect_timeout': 15, 'keepalives': 1, 'keepalives_idle': 60, 'keepalives_interval': 15, 'keepalives_count': 4})), endpoint=prefix.lower().rstrip('_'))

def render(path: Path, start: date, end: date) -> str:
    return path.read_text(encoding='utf-8').strip().rstrip(';').replace('$1::date', f"DATE '{start}'").replace('$2::date', f"DATE '{end}'")

def statements(path: Path) -> list[str]:
    return [x.strip() for x in '\n'.join(l for l in path.read_text(encoding='utf-8').splitlines() if not l.lstrip().startswith('--')).split(';') if x.strip()]

def reader(snapshot: str, name: str):
    source = open_db('SOURCE_', name)
    try:
        with source.cursor() as cur:
            cur.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            cur.execute(sql.SQL('SET TRANSACTION SNAPSHOT {}').format(sql.Literal(snapshot)))
            cur.execute(f"SET LOCAL statement_timeout = '{TIMEOUT}s'")
            cur.execute(f"SET LOCAL work_mem = '{SOURCE_WORK_MEM}'")
        return source
    except Exception:
        source.close(); raise

def control(cur, start: date, end: date) -> dict[str, object]:
    query = render(CONTROLS, start, end)
    cur.execute(query); row = cur.fetchone()
    if row is None: raise RuntimeError('source controls returned no row')
    return dict(zip((x.name for x in cur.description), row, strict=True))

def months(start: date, end: date):
    day = start
    while day < end:
        nxt = date(day.year + (day.month == 12), day.month % 12 + 1, 1)
        yield day, min(nxt, end); day = nxt

def plan(start: date, end: date) -> None:
    with open_db('SOURCE_', 'employee_presence_day_plan') as source, source.cursor() as cur:
        cur.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY')
        cur.execute(f"SET LOCAL statement_timeout = '{TIMEOUT}s'")
        cur.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + render(EXTRACT, start, end))
        p = cur.fetchone()[0][0]
        print(f"SOURCE_PLAN start={start} end={end} rows={p['Plan'].get('Actual Rows')} execution_ms={p['Execution Time']:.3f} planning_ms={p['Planning Time']:.3f}")

def copy_out(snapshot: str, start: date, end: date, path: Path) -> int:
    with reader(snapshot, 'employee_presence_day_copy') as source, source.cursor() as cur, path.open('wb') as out:
        with cur.copy(f'COPY ({render(EXTRACT, start, end)}) TO STDOUT WITH (FORMAT BINARY)') as copied:
            for block in copied: out.write(block)
        return cur.rowcount

def reconcile(cur, expected: dict[str, object], start: date, end: date) -> None:
    body = '\n'.join(l for l in RECON.read_text(encoding='utf-8').splitlines() if not l.lstrip().startswith('--'))
    values = (expected['target_grain_rows'], expected['total_presence_minutes'], expected['min_presence_date'], expected['max_presence_date'], start, end)
    cur.execute(re.sub(r'\$\d+', '%s', body), tuple(values[int(x.group(1)) - 1] for x in re.finditer(r'\$(\d+)', body)))
    failed = [r[:3] for r in cur.fetchall() if r[3] != 'PASS']
    if failed: raise RuntimeError(f'target reconciliation failed: {failed}')

def load(initial: bool) -> None:
    start, end = br003_horizon(datetime.now(ZoneInfo('Europe/Moscow')).date())
    if shutil.disk_usage('/tmp').free < 1_073_741_824: raise RuntimeError('Less than 1GiB free for COPY files')
    owner = open_db('SOURCE_', 'employee_presence_day_snapshot_owner')
    target = None
    try:
        with owner.cursor() as cur:
            cur.execute('BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY'); cur.execute(f"SET LOCAL statement_timeout = '{TIMEOUT}s'"); cur.execute(f"SET LOCAL work_mem = '{SOURCE_WORK_MEM}'")
            cur.execute('SELECT pg_export_snapshot()'); snapshot = cur.fetchone()[0]
            expected = control(cur, start, end)
        with tempfile.TemporaryDirectory(prefix='employee_presence_day_') as temp:
            batches = []
            for number, (batch_start, batch_end) in enumerate(months(start, end), 1):
                path = Path(temp) / f'{number:02d}.copy'; rows = copy_out(snapshot, batch_start, batch_end, path)
                print(f'SOURCE_COPY batch={batch_start}:{batch_end} rows={rows} bytes={path.stat().st_size}', flush=True); batches.append((path, rows))
            if sum(rows for _, rows in batches) != int(expected['target_grain_rows']): raise RuntimeError('source COPY rows differ from independent expected rows')
            target = open_db('MART_', 'employee_presence_day_target')
            with target.cursor() as cur:
                cur.execute('BEGIN'); cur.execute(f"SET LOCAL statement_timeout = '{TIMEOUT}s'"); cur.execute("SET LOCAL lock_timeout = '300s'")
                cur.execute('SELECT pg_advisory_xact_lock(hashtext(%s))', (TARGET + ':refresh',))
                cur.execute('SELECT to_regclass(%s)', (TARGET,)); exists = cur.fetchone()[0] is not None
                if initial == exists: raise RuntimeError('target state does not match initial/rerun mode')
                if initial:
                    for stmt in statements(DDL): cur.execute(stmt)
                cur.execute(f'CREATE TEMP TABLE {STAGE} (LIKE {TARGET} INCLUDING DEFAULTS) ON COMMIT DROP')
                copied = 0
                for path, expected_rows in batches:
                    with path.open('rb') as inp, cur.copy(f'COPY {STAGE} ({COLUMNS}) FROM STDIN WITH (FORMAT BINARY)') as cp:
                        while block := inp.read(1_048_576): cp.write(block)
                    if cur.rowcount != expected_rows: raise RuntimeError('target COPY row count differs')
                    copied += cur.rowcount
                if copied != int(expected['target_grain_rows']): raise RuntimeError('staged rows differ from expected')
                cur.execute(f'DELETE FROM {TARGET}'); cur.execute(f'INSERT INTO {TARGET} ({COLUMNS}) SELECT {COLUMNS} FROM {STAGE}')
                reconcile(cur, expected, start, end); target.commit()
        with target.cursor() as cur:
            cur.execute(f'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT presence_date, club_id, employee_id, presence_minutes FROM {TARGET} WHERE presence_date >= %s AND presence_date < %s', (start, end))
            p = cur.fetchone()[0][0]; print(f"TARGET_PLAN rows={p['Plan'].get('Actual Rows')} execution_ms={p['Execution Time']:.3f}")
        print(f"LOAD_PASS rows={expected['target_grain_rows']} minutes={expected['total_presence_minutes']} no_link={expected['no_link_visit_ids']} multi_link={expected['multi_link_visit_ids']}")
    except Exception:
        if target: target.rollback()
        raise
    finally:
        owner.rollback(); owner.close()
        if target: target.close()

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('--plan', nargs=2, metavar=('START', 'END')); p.add_argument('--initial', action='store_true'); p.add_argument('--rerun', action='store_true'); a = p.parse_args()
    if a.plan:
        plan(date.fromisoformat(a.plan[0]), date.fromisoformat(a.plan[1])); return
    if a.initial == a.rerun: p.error('choose --plan or exactly one of --initial/--rerun')
    load(a.initial)
if __name__ == '__main__': main()
