# Авторизация revised Stage 3 planning: `employee_presence_day`

- Пакет: `employee_presence_stage3_revised_planning_2026-08-28`
- Отчёт: `employee_workload`
- Технический этап реестра: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Основание: пользователь подтвердил продолжение после BR-045.

## Scope

Подготовить один immutable reviewed set для `mart.employee_presence_day`:

1. обновить mapping, ADR, data contract и catalog для grain
   `employee × presence_date × club`;
2. подготовить revised source extract, независимые source controls, reviewed
   DDL, rollback/transport plan и target reconciliation plan;
3. задокументировать будущую performance ladder для exact extract.

В personal domain входят qualified visits с хотя бы одной `Reference225`
карточкой; `employee_id` — `MIN(_idrref)` по client. Visits без любой карточки
исключаются по BR-044.

## Boundaries

Не разрешены source/target DDL/DML, `COPY`, transport, target connection,
full-range source plan, Power BI/M/DAX change, внешние файлы или изменения 1С.
Sample `EXPLAIN ANALYZE` и actual source controls не входят в этот пакет и
остаются для отдельного physical admission. Existing two-product SQL remains
superseded and must not be executed.

## Closure criterion

Созданы reviewed immutable mapping, ADR, contract, one-product extract,
independent source-control, DDL and reconciliation/rollback artifacts; every
column has source, transform, type, NULL-policy, grain and evidence. Physical
admission remains a separate explicit approval.
