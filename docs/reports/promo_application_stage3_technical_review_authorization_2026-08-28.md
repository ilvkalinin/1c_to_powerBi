# Авторизация Stage 3 technical review: `mart.promo_application`

- Дата: 2026-08-28
- Пакет: `promo_application_stage3_technical_review_2026-08-28`
- Этап: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Отчёт: `promo_codes`
- Основание: пользователь согласовал «legacy output» и поручил довести витрину
  до конца по правилам, шаблонам тестирования и оптимизации.

## Разрешённый scope

Подготовить reviewed immutable set для будущей physical delivery:

- зафиксировать BR-046: grain первого релиза — post-M report row, который
  сохраняет branch-specific `MAX`/`SUM`/`Table.Distinct`, а не произвольную
  строку source movement;
- проверить mapping/data contract/ADR по точному local PBIT и full M/DAX
  source; создать source extract, независимые controls, DDL, atomic loader,
  target reconciliation и evidence matrix;
- выполнить только read-only source metadata/cardinality проверки и
  `EXPLAIN (ANALYZE, BUFFERS)` точного extract на короткой representative
  выборке согласно шаблону подготовки и оптимизации.

Пакет не выполняет target connection, DDL/DML, `COPY`, full-range transport,
Power BI/M/DAX change или изменение 1С. Физическая поставка потребует
отдельного admission с immutable links, перечнем операций, rollback и
критерием приёмки.

## Критерий закрытия

Все target columns mapped without `UNKNOWN`; agreed report grain/key and
legacy multiplicity are explicit; reviewed local SQL set and reconciliation
matrix exist; representative exact-extract plan is recorded. No target state
is changed.
