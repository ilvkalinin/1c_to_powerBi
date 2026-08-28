# Авторизация Stage 3 product admission: `mart.fitness_funnel_client_start`

- Дата: 2026-08-28
- Пакет: `fitness_funnel_client_start_stage3_product_admission_2026-08-28`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёт: № 11 «Фитнес воронка» (`fitness_funnel`)
- Основание: пользователь подтвердил создание витрины до конца со всеми
  правилами тестирования и оптимизации в задаче 2026-08-28.

## Разрешённый scope

Выполнить физическую поставку только `mart.fitness_funnel_client_start` по
immutable technical-review set:

- [source extract](../../sql/marts/fitness_funnel_client_start_source_extract.sql),
  [source controls](../../sql/marts/fitness_funnel_client_start_source_controls.sql),
  [DDL](../../sql/marts/fitness_funnel_client_start_ddl.sql),
  [guarded runner](../../scripts/load_fitness_funnel_client_start.py) и
  [target reconciliation](../../sql/tests/fitness_funnel_client_start_reconciliation.sql);
- выполнить FF-S01—FF-S03 на полном legacy horizon от `2024-01-01`, exact
  progressive source-plan ladder и только после успешной ladder измерить
  full-range baseline и derived binary-COPY cap;
- создать `mart` при отсутствии и `mart.fitness_funnel_client_start`, выполнить
  atomic `DELETE + INSERT` из temporary stage, FF-R01—FF-R07, target read plan
  и atomic rerun с controls его собственного source snapshot;
- сохранить source/stage/target evidence, rollback evidence и результат
  connection/transport measurements.

## Точные операции и rollback

DDL: `CREATE SCHEMA IF NOT EXISTS mart`; `CREATE TABLE
mart.fitness_funnel_client_start`; `REVOKE ALL ... FROM PUBLIC`. Каждая
загрузка выполняется одним target transaction под transaction-scoped advisory
lock: temporary stage получает derived binary COPY, затем `DELETE FROM
mart.fitness_funnel_client_start` и `INSERT ... SELECT` followed by FF-R01—FF-R07.
Любая ошибка до commit откатывает DDL/DML и сохраняет прежний target snapshot;
temporary COPY file удаляется. `DROP`, raw replication, source DDL/indexes,
`mart.fitness_funnel_client_outcome` и Power BI changes запрещены.

## Критерий закрытия

FF-S01—FF-S03 и FF-R01—FF-R07 имеют нулевые deviations в каждом запуске;
source full plan, derived-COPY cap, target read plan и two atomic runs recorded;
logical key, contract, horizon and PII boundary pass. Full rebuild is reported
only as a measured baseline, never as an incremental SLA.
