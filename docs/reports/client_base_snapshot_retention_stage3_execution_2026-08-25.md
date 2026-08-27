# Stage 3 execution: client-base snapshot and retention

Статус: `VALIDATED`.

## Successful direct-route atomic rerun (2026-08-27)

После перехода рабочей станции в корпоративную сеть прямой маршрут к обоим
PostgreSQL endpoints был подтверждён через `en0`; OpenVPN Connect не участвовал
в этом rerun. `--rerun` создал новый `REPEATABLE READ, READ ONLY` source
snapshot и прошёл 20 месячных интервалов `2025-01-01..2026-08-28` для каждой
facts. Каждый из 40 source fact-month пакетов прошёл independent source control
до binary COPY; повторных source выгрузок и transport retries не было.

Target transport preflight прошёл 3/3. Затем в одной target transaction были
загружены временные stages, выполнена замена обоих facts и pre-commit
reconciliation `4/4 PASS`. Commit завершился за 1280.215 s от начала source
snapshot: `mart.client_base_snapshot` — 1 590 169 строк,
`mart.client_base_retention` — 1 101 391 строк. Post-commit reconciliation
также `4/4 PASS`; target read plans: snapshot 3.443 ms, retention 1.322 ms.

Отдельный final-horizon audit подтвердил обе facts: диапазон
`2025-01-01..2026-08-24`, future rows = 0. Power BI не изменялся.

## Future-date correction (2026-08-26)

Пользователь уточнил BR-003: «текущий год» означает данные от начала года
по текущую московскую дату, а не плановые строки до конца года. Верхняя
исключающая граница каждого общего loader-а изменена на динамический
today + 1 day; на 2026-08-26 это 2026-08-27. Два live-SQL обхода с
жёстким 2027-01-01 в preparation_renewal_checkpoint параметризованы
через $2.

Перед cleanup был выполнен rollback-only monthly DELETE probe:
mart.client_base_daily, 2026-08-27..2026-09-01, 25.732 ms,
12 945 shared hits / 173 reads. После mart preflight 3/3 один atomic cleanup
удалил ровно 876 393 future-строки и postcheck по всем наборам дал ноль:
client_base_daily 310 592; client_base_snapshot 153 586;
client_base_retention 227 911; membership_contract_kpi_unit 1;
newcomer_engagement_milestone 21 341;
newcomer_engagement_second_month 13 018;
preparation_renewal_checkpoint 149 944. Затем выполнен ANALYZE только
этих семи facts. Post-cleanup read plans: daily 4.310 ms, snapshot 1.414 ms,
retention 0.271 ms. Power BI не изменялся.

## Committed initial load

`scripts/load_client_base_snapshot_retention.py --initial-load` завершил одну
target transaction после monthly bounded binary COPY и independent controls.

| Fact | Committed rows | Source/stage/target reconciliation |
|---|---:|---|
| `mart.client_base_snapshot` | 1 743 765 | PASS |
| `mart.client_base_retention` | 1 329 302 | PASS |

Post-commit contract reconciliation: 4/4 PASS. Target read plans: snapshot
10.949 ms; retention 2.286 ms. Power BI не изменялся.

## Rerun transport diagnosis

The source query plan is not the blocker. Monthly source batches measured
7.6--12.6 MB / 20.8--25.3 s for retention and 7.8--12.6 MB / 12.0--15.3 s
for snapshot; all are well below the user-approved 180-second cap.

On 2026-08-25 a rerun passed eight retention months and then repeated the
failure on the September snapshot reader: source `pg_stat_activity` was
`active / ClientWrite`, target was `idle in transaction / ClientRead`, and
the source COPY file remained exactly 0 bytes. Thus PostgreSQL had started to
write the COPY stream but no byte reached the local process; the target had
not received a partial month. The 180-second watchdog emitted its timeout,
but libpq cancellation did not return a client whose TCP stream was already
stalled. Only termination of the owned source backend and local runner cleared
the transaction; target advisory locks then returned to 0 and committed rows
remained 1 743 765 / 1 329 302.

The network condition was then reproduced without SQL or COPY: raw TCP
connects to both source `172.16.126.73:5432` and mart `172.16.126.214:5432`
timed out. Both routes resolved to gateway `192.168.50.1` via `en0`; the local
interface and gateway answered ICMP, while an active `utun6` VPN interface did
not own a route to the `172.16.126.0/24` database subnet. This is evidence of
a split-route/VPN or upstream gateway path failure, not a PostgreSQL setting,
query plan, binary format, transferred-byte volume, or target aggregation.

## Preventive runner changes

`scripts/load_client_base_snapshot_retention.py` now keeps one read-only
`REPEATABLE READ` source owner and exports its snapshot. Every fact-month is
then read by a new isolated source process attached to that same snapshot.
The parent gives that process a hard 180-second wall-clock cap; a failure kills
the process/socket before retrying a new connection, so a stuck COPY cannot
hold the target transaction or reuse a poisoned transport. The reader has a
15-second libpq admission timeout, five delayed admission retries, TCP
keepalives (60/15/4) and `tcp_user_timeout=180s`. Retention readers retain the
measured `work_mem=128MB` setting. `psycopg2-binary==2.9.12` is declared for
the source binary COPY worker.

All runner connections (source owner, source readers, child workers and mart
target) now load the repository-root ignored `.env` themselves before any
socket is opened. The file is authoritative for `SOURCE_*` and `MART_*`;
stale shell environment values cannot redirect this package. The loader is
centralised in `scripts/mart_connection.py` and covers every current
PostgreSQL client script, including the three standalone loaders. An `env -i`
probe with deliberately false inherited hosts passed for all 21 database
clients without printing credentials.

The exported-snapshot handoff was validated by a source reader probe. The
subsequent completed rerun and its final controls are recorded above; no
partial rerun state was committed by the failed attempts.

## Intermittent-route rerun evidence

After both endpoint TCP probes recovered, a fresh rerun was started without
shell-exported credentials; the runner loaded `.env` itself. It completed all
snapshot months from `2025-01` through `2026-06` and all retention months from
`2025-01` through `2026-05` using a new reader process for every fact-month.
The largest observed monthly source batch was 12.6 MB / 16.1 s (snapshot) and
9.4 MB / 27.9 s (retention); no batch approached the 180-second cap.

During retention `2026-06`, the first two isolated source workers exited with
transport failure and the source owner plus mart target sockets then timed out.
The parent did not hang: it retried the same source snapshot, and no target
replace or commit occurred. As TCP to both endpoints was unavailable again,
the target server's disconnect rollback cannot be queried until connectivity
returns. The runner now also applies the 15-second admission timeout,
keepalives and TCP user timeout to the mart connection, and records an
unavailable rollback without masking the original transport failure.

The runner deliberately does not perform blind full retries after a transport
failure: it closes its owned source/target session, reports
`automatic_full_restart=disabled`, and leaves the committed facts intact. A
new whole attempt gets a new source snapshot only after a fresh three-sample
endpoint preflight. The target transaction has a 240-second idle-in-transaction
timeout, so an orphaned target session releases its advisory lock.

Route evidence rules out a random SQL/COPY failure: while both endpoints timed
out, `172.16.126.73` and `172.16.126.214` resolved through
`en0 -> 192.168.50.1`. When raw TCP recovered, the same destinations resolved
through VPN tunnel `utun5 -> 192.168.126.225`. The intermittent split-route/
VPN path for `172.16.126.0/24` is therefore the observed fault domain.
