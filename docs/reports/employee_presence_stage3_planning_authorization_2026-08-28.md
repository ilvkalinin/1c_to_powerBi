# Авторизация Stage 3 planning: presence products

- Пакет: `employee_presence_stage3_planning_2026-08-28`
- Отчёт: `employee_workload`
- Технический этап реестра: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Основание: пользователь явно подтвердил Stage 3 planning-пакет для двух
  presence-продуктов.

## Scope

Подготовить единый immutable reviewed set для:

1. персонального `mart.employee_presence_day` с grain
   `employee × presence_date × club` только для exact-one employee domain;
2. отдельного `mart.employee_presence_unattributed_day` с grain
   `presence_date × club × attribution_status` и без `employee_id`, где
   `attribution_status` равен только `NO_EMPLOYEE` или
   `MULTIPLE_EMPLOYEES` по BR-043.

Разрешены mapping/ADR/contracts, exact source extracts, source controls,
DDL, rollback, bounded transport/loader and target reconciliation plan, а
также один безопасный representative `EXPLAIN (ANALYZE, BUFFERS)` точного
source extract после фиксации SQL. Все source statements — fresh
`REPEATABLE READ, READ ONLY` через `connect_with_retry`.

## Boundaries

Не разрешены target connection, создание/изменение объектов, DDL/DML, `COPY`,
transport, full-range source plan, Power BI/M/DAX change, внешний-file review,
индексы или изменение VM-1. No employee fallback/tie-break is permitted.

## Closure criterion

Созданы reviewed immutable mapping, ADR, contracts, extract, independent
source controls, DDL, loader/rollback and reconciliation artifacts; every SQL
column has source, transform, type, NULL-policy, grain and evidence; the
representative source plan is recorded or marked `BLOCKED`; physical admission
remains a separate user approval.
