# Incremental design: `mart.client_base_daily`

Статус: `INCREMENTAL_CANDIDATE / IMPLEMENTATION_NOT_EXECUTED`.

## Separate runner

Новый `scripts/load_client_base_daily_incremental.py` и
`config/client_base_daily_incremental.json` не вызывают и не изменяют
`scripts/load_client_base_daily.py`. В orchestration manifest у job
`client_base_daily` указан только новый entrypoint с `--run`; его
`scheduling_status` остаётся `BLOCKED` до окончания проектирования всех jobs
и отдельного installation package.

## Change detection and correctness

Все изменения, удаления и поздние исправления определяются не по неполному
source watermark, а сравнением source и target для каждой даты BR-003.
Источник формирует только семь уже контрактных агрегатных полей. Для каждой
даты вычисляются число строк и два детерминированных `md5` над разными
каноническими порядками строк; состояние не записывается отдельно и сырые
регистры/ID клиентов не покидают VM-1.

Если отпечатки совпали, runner завершает `NO_CHANGES` без target DML. Если
они отличаются, он заменяет атомарно минимальный непрерывный диапазон от
первой до последней изменившейся даты. До `COMMIT` он выполняет existing
independent daily scope controls, BR-038 child-package control, stage key/
contract checks и повторное сравнение полного BR-003 fingerprint. Поэтому
digest выбирает даты, а не подменяет source-to-target reconciliation.

`sql/marts/client_base_daily_incremental_source_fingerprint.sql` является
runtime template: runner вставляет в маркер единственный reviewed
`client_base_daily_extract.sql`; второй extract не поддерживается. Target
replacement также отдельный:
`sql/marts/client_base_daily_incremental_target_replace.sql`.

## Read-only evidence

| Exact fingerprint horizon | Dates | Time | I/O |
|---|---:|---:|---|
| `2026-07-01..2026-08-01` | 31 | 17.882 s | shared read 58,608; temp read/write 1,254 / 2,857 blocks |
| `2025-01-01..2026-09-01` | 608 | 30.850 s | shared read 0; temp read/write 56,957 / 88,961 blocks |

Both plans used independent `REPEATABLE READ, READ ONLY` source sessions with
a 120-second statement limit. No transport ran concurrently.

The new `--check-only` mode executed without DML and found 608 differing
dates. A row-level one-day check on `2026-08-01` proved that this is real,
not a fingerprint encoding error: both sides have 2,446 aggregate rows, but
44 source rows and 44 target rows differ. Independent daily totals were
`club 94,889 / 94,891` and `network 94,791 / 94,792` (source / target).

The first approved `--run` will therefore replace the full current BR-003
range as a correction through this separate runner. Later executions can
replace a shorter span, but no daily SLA is claimed until a write-run and
post-commit target read plan are separately measured.

## Rollback and safeguards

The runner requires the existing target and BR-038 constraint, takes the
same advisory lock as the full loader, stages before deletion, and rolls back
the whole target transaction on any source, COPY, contract, control or digest
failure. It never runs DDL, does not alter source data, and refuses an
unvalidated watermark or SLA in its configuration.
