# S3-CBD-PKG-001: детские пакеты в `mart.client_base_daily`

- Дата одобрения: 2026-08-25
- Отчёт: `client_base`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Пакет: `client_base_children_packages_implementation_2026-08-25`
- Основание: пользователь подтвердил полный implementation-пакет после
  read-only review CB-PKG-001—003.

## Цель и неизменяемый scope

Включить package-only детей в существующий агрегированный факт
`mart.client_base_daily`, не меняя его grain, семь target columns, Power BI,
источники 1С или создавая raw-копию на VM-2. Для child-package ветви
используется BR-037: sales-группа с неположительными amount/quantity не входит;
несколько положительных, не возвращённых продаж `договор × ребёнок` получают
максимальную `GREATEST(дата начала договора, дата чека)`; при физическом
отсутствии sales-группы child-row сохраняется. По BR-038 любой valid
child-package interval получает `age_group = 'Дети'` при фактическом возрасте;
при пересечении с обычным membership package-interval имеет приоритет, без
двойного client-day. Разрешённая минимальная DDL меняет только age `CHECK`, не
grain и не набор колонок.

## Reviewed implementation set

- Mapping: `docs/mappings/client_base.md`.
- Design: `docs/adr/0031-client-base-daily-denominator.md`.
- Data contract: `docs/data_contracts/client_base.md`.
- Source extract: `sql/marts/client_base_daily_extract.sql`.
- Independent source controls: `sql/marts/client_base_daily_source_controls.sql`.
- Runner: `scripts/load_client_base_daily.py --rebuild`; monthly bounded binary
  batches in one source `REPEATABLE READ READ ONLY` snapshot and one target
  transaction.
- Target DML: `sql/marts/client_base_daily_target_replace.sql` (`DELETE` BR-003
  horizon, `INSERT` from temporary stage).
- Reviewed DDL/rollback: `sql/marts/client_base_daily_child_package_age_ddl.sql`;
  в target transaction заменяется только `client_base_daily_age_ck`.
- Acceptance tests: `sql/tests/client_base_daily_reconciliation.sql`.

## Разрешённые операции и rollback

1. До full-range исполнения выполнить exact sample `EXPLAIN (ANALYZE, BUFFERS)`
   нового extract на репрезентативном месяце и зафиксировать rows/time/I/O.
2. Затем получить full-range baseline и independent source controls в том же
   source snapshot, передать только месячные агрегированные COPY-порции через
   один удаляемый временный binary file и проверить каждую порцию.
3. Под advisory lock создать только target temporary stage/expected tables;
   после stage controls в одной target transaction применить reviewed
   `client_base_daily_age_ck` DDL, удалить BR-003 строки и вставить проверенные
   агрегаты. Ошибка до `COMMIT` делает `ROLLBACK`, включая DDL, и оставляет
   previous production snapshot; `DROP TABLE` не выполняется.
4. Выполнить same-run target reconciliation, target read-plan и полный atomic
   rerun с собственными source controls. Power BI остаётся вне scope по BR-036.

## Критерий закрытия

Для каждого прогона: source/stage/target controls равны с tolerance 0;
package-only child coverage и BR-037 return/repeat-start controls проходят;
logical key, NULL/range/age/type contract и horizon имеют нулевые отклонения;
full rerun успешен. В evidence записаны sample/full performance, batch rows and
bytes, target read-plan/size и отсутствие Power BI изменений. Full rebuild не
объявляется incremental SLA.

## Фактический статус

Initial BR-037 atomic run and post-commit source/stage/target controls passed.
Пользователь подтвердил BR-038 для всех packages; pending work — reviewed DDL,
priority rebuild and atomic rerun. See [execution evidence](client_base_children_packages_execution_2026-08-25.md).
