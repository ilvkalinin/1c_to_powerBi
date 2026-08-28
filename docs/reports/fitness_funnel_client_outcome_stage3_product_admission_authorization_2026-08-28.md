# Авторизация Stage 3 product admission: `mart.fitness_funnel_client_outcome`

- Дата: 2026-08-28
- Пакет: `fitness_funnel_client_outcome_stage3_product_admission_2026-08-28`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёт: № 11 «Фитнес воронка» (`fitness_funnel`)
- Основание: пользователь 2026-08-28: «добрабатывай до конца разработки
  витрины».

## Разрешённый scope

Выполнить физическую поставку только `mart.fitness_funnel_client_outcome`:

- доработать reviewed
  [source controls](../../sql/marts/fitness_funnel_client_outcome_source_controls.sql),
  [guarded runner](../../scripts/load_fitness_funnel_client_outcome.py) и
  [target reconciliation](../../sql/tests/fitness_funnel_client_outcome_reconciliation.sql),
  чтобы expected rows по пяти source-ветвям вычислялись отдельным source path,
  а не проверяемым extract;
- выполнить exact progressive `EXPLAIN (ANALYZE, BUFFERS)` текущего source
  extract на ограниченном окне; только после успешного sample определить
  current full-range baseline, объём derived binary COPY и его cap;
- в исходном `REPEATABLE READ, READ ONLY` snapshot получить independent
  controls и выгрузить лишь contract-колонки месячными source-first файлами
  из одного exported snapshot; суммарный cap пула — `512 MiB`, target не
  открывается до готовности всего пула;
  [source extract](../../sql/marts/fitness_funnel_client_outcome_source_extract.sql);
- создать при отсутствии схему `mart` и таблицу по
  [DDL](../../sql/marts/fitness_funnel_client_outcome_ddl.sql), затем в одной
  target-транзакции под advisory lock выполнить temporary-stage binary COPY,
  `DELETE + INSERT`, target reconciliation, commit только при нулевых
  отклонениях, target read plan и atomic rerun;
- задокументировать snapshot, rows, bytes, планы, target size, retry/cleanup,
  rollback и результаты сверок.

## Точные операции и rollback

Разрешены `CREATE SCHEMA IF NOT EXISTS mart`, `CREATE TABLE
mart.fitness_funnel_client_outcome`, `REVOKE ALL ... FROM PUBLIC`, временная
stage-таблица, binary `COPY`, `DELETE` и `INSERT` только для этой витрины.
Target-операции выполняются в одной транзакции под transaction-scoped advisory
lock. Любая ошибка до commit откатывает DDL/DML и сохраняет прежний target
snapshot; весь derived месячный pool удаляется. Запрещены `DROP`, raw-реплика
1С, source DDL/indexes, изменения иных mart-объектов и Power BI.

## Критерий закрытия

Independent source controls и target checks имеют нулевые deviations в двух
atomic runs; логический ключ, contract, branch rows, horizon, source states,
cleanup и rollback подтверждены. Записаны sample/full source plan, derived
COPY cap, target read plan и размер таблицы. Результат называется только
full-rebuild baseline; incremental SLA не заявляется.
