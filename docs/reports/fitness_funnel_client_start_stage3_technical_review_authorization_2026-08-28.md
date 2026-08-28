# Авторизация Stage 3 technical review: `mart.fitness_funnel_client_start`

- Дата: 2026-08-28
- Пакет: `fitness_funnel_client_start_stage3_technical_review_2026-08-28`
- Этап: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Отчёт: № 11 «Фитнес воронка» (`fitness_funnel`)
- Основание: пользователь подтвердил пакет в задаче 2026-08-28.

## Разрешённый scope

Подготовить один reviewed immutable set для будущей physical delivery
`mart.fitness_funnel_client_start`:

- сверить mapping, ADR-0026 и data contract с first-release семантикой
  cohort: один `client_key × membership_start_date`; несколько допустимых
  договоров в группе не увеличивают число клиентов и не выбирают «главный»
  договор;
- выполнить на VM-1 только короткие read-only metadata/cardinality/state
  проверки `Reference59`, `Reference141X1` и `Reference132`, включая
  однородность club/tenure атрибутов в multi-contract cohort groups;
- выполнить `EXPLAIN (ANALYZE, BUFFERS)` точного bounded source extract в
  отдельном `REPEATABLE READ, READ ONLY` snapshot; записать horizon, rows,
  time, I/O и connection outcome;
- подготовить versioned source extract, independent source controls, DDL,
  atomic future loader, rollback strategy, target reconciliation и admission
  evidence matrix.

## Границы автономной работы

Пакет не выполняет target connection, DDL, DML, `COPY`, full-range transport,
Power BI/M/DAX change, анализ Excel/Power Query, изменение источника 1С или
работу над `mart.fitness_funnel_client_outcome`. Физическая admission потребует
отдельного пользовательского одобрения immutable reviewed SQL, перечня
операций, rollback и критериев приёмки.

## Критерий закрытия

Все колонки будущего cohort contract имеют подтверждённые source,
transformation, PostgreSQL type, NULL-policy и test; grain/key/risky joins и
source states явно зафиксированы; существуют reviewed local SQL set и
reconciliation matrix; representative exact-extract plan записан. Если
multi-contract cohort требует выбрать расходящиеся display-атрибуты, пакет
закрывается одним документированным `DECISION_REQUIRED` без physical SQL. На
VM-2 нет созданных или изменённых объектов.
