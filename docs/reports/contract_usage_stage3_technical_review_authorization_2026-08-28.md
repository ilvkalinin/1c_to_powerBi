# Авторизация Stage 3 technical review: `mart.contract_usage`

- Дата: 2026-08-28
- Пакет: `contract_usage_stage3_technical_review_2026-08-28`
- Этап: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Отчёт: № 17 «Отчёт по %Renew» (`renew_contract_usage`)
- Основание: пользователь подтвердил пакет в задаче 2026-08-28.

## Разрешённый scope

Подготовить один reviewed immutable set для будущей physical delivery
`mart.contract_usage`:

- сверить mapping, ADR-0006 и data contract с закреплённой first-release
  семантикой: один контракт, current годовое окно, `COUNT(*)`, `Fld693` без
  методической подмены и без переключения Power BI;
- выполнить на VM-1 только короткие read-only metadata/cardinality/state
  проверки, независимые source controls и `EXPLAIN (ANALYZE, BUFFERS)` точного
  extract на representative bounded horizon;
- подготовить versioned source extract, independent source controls, DDL,
  atomic loader, rollback strategy, target reconciliation и admission evidence
  matrix;
- зафиксировать measured plan, границы sample, rows, time, I/O, отсутствие
  параллельного transport и все нерешённые риски.

## Границы автономной работы

Пакет не выполняет target connection, DDL, DML, `COPY`, full-range transport,
Power BI/M/DAX change, анализ Excel/Power Query или изменение источника 1С.
Полная physical admission потребует отдельного пользовательского одобрения
immutable reviewed SQL, точного перечня операций, rollback и критериев
приёмки.

## Критерий закрытия

Все колонки будущего physical contract имеют подтверждённые source,
transformation, PostgreSQL type, NULL-policy и test; grain/key/risky joins и
source states явно зафиксированы; существуют reviewed local SQL set и
reconciliation matrix; representative exact-extract plan записан. На VM-2 нет
созданных или изменённых объектов.
