# Авторизация physical admission: `mart.employee_presence_day`

- Пакет: `employee_presence_day_stage3_product_admission_2026-08-28`
- Отчёт: `employee_workload`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Основание: явное решение пользователя «давай до конца по алгоритмы
  тестирования оптимизации без дальнейших согласований».

## Immutable reviewed inputs

- [mapping](../mappings/employee_workload.md), [contract](../data_contracts/employee_workload.md),
  [ADR](../adr/0014-employee-workload-multi-fact.md), [BR-044/BR-045](../catalogs/business_rules.md);
- [source extract](../../sql/marts/employee_presence_day_br045_extract.sql),
  [independent controls](../../sql/marts/employee_presence_day_br045_source_controls.sql),
  [DDL](../../sql/marts/employee_presence_day_br045_ddl.sql),
  [reconciliation](../../sql/tests/employee_presence_day_br045_reconciliation.sql).

## Approved operations

1. Build and test a loader using `connect_with_retry`, fresh source
   `REPEATABLE READ, READ ONLY` sessions, temporary derived binary COPY files,
   a short target transaction, advisory lock, temporary stage and cleanup.
2. Run independent source controls and an exact one-month
   `EXPLAIN (ANALYZE, BUFFERS)`; continue the 1→2→3→6-month ladder and one
   full source plan only while the preceding step succeeds without stop signal.
3. Execute initial target DDL/load, in-transaction source/stage/target
   reconciliation, atomic rollback on any failure, target read plan and atomic
   rerun with controls from its own source snapshot.
4. Record performance, rows, bytes, source/target controls, lock/rollback and
   Power BI boundary in execution evidence; implement only an optimization
   supported by a before/after exact plan and equal results.

## Boundaries and closure

No change to 1C source, no source index, raw replica, external-file review or
Power BI/M/DAX work. Full rebuild is a baseline only; no incremental SLA is
claimed. Closure requires zero deviations, committed initial load and rerun,
measured source and target plans, cleanup and a complete execution report.
