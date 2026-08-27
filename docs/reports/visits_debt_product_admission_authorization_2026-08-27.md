# Авторизация Stage 3: движения долга по неподтверждённым услугам

- Дата: 2026-08-27
- Пакет: `visits_debt_product_admission_2026-08-27`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёт: `visits_debt`
- Основание: пользователь явно подтвердил единый Stage 3 пакет после выбора
  `mart.unconfirmed_service_debt_movement` следующим продуктом реализации.

## Разрешённый scope

Выполнить полный reuse review, зафиксировать immutable mapping/ADR/data contract,
source extract, independent source controls, DDL, atomic loader, reconciliation
и rollback для одной новой physical fact
`mart.unconfirmed_service_debt_movement`. Grain — одно движение
`AccumRg7509`: период × регистратор × номер строки. `mart.visit_client_day`
переиспользуется только как отдельная cohort dependency, без PII и без смешения
с движениями. Power BI и источник 1С не изменяются.

До DDL/COPY обязательны: полное подтверждение mapped columns, source states,
logical key, document-branch cardinality и as-of controls; точный source
`EXPLAIN (ANALYZE, BUFFERS)` на репрезентативном месячном sample; затем
full-range baseline, measured bounded binary transport и independent expected
controls в одном read-only source snapshot. Target DDL/load/rerun проходят
атомарно с rollback при любом control failure.

## Immutable reviewed set и transport

- [Mapping](../mappings/visits_debt.md), [ADR-0021](../adr/0021-visit-debt-movement.md)
  и [contract](../data_contracts/visits_debt.md): один physical movement fact;
  `mart.visit_client_day` только reuse для cohort, без смешения grain.
- [Exact source extract](../../sql/marts/unconfirmed_service_debt_movement_extract.sql):
  две current-M document branches `UNION ALL`, сервисы `NOT ILIKE 'Купон%'`,
  sign-case `RecordKind=1 → -amount`; новый state-filter и dedupe не вводятся.
- [Independent source controls](../../sql/marts/unconfirmed_service_debt_movement_source_control.sql):
  отдельная branch-map aggregation, не extract path; rows, keys, sum и min/max
  снимаются до каждого binary COPY.
- [DDL](../../sql/marts/unconfirmed_service_debt_movement_ddl.sql),
  [replace](../../sql/marts/unconfirmed_service_debt_movement_target_replace.sql),
  [reconciliation](../../sql/tests/unconfirmed_service_debt_movement_reconciliation.sql)
  и [loader](../../scripts/load_unconfirmed_service_debt_movement.py): один
  target transaction с advisory lock, temporary stage, `DELETE + INSERT`,
  rollback до commit; удаление объекта автоматикой запрещено.

Transport открывает один `REPEATABLE READ, READ ONLY` source snapshot. Для
каждого календарного месяца reader подключается заново к этому snapshot,
сначала получает independent control, затем сохраняет один binary COPY buffer,
закрывает source reader, копирует buffer в target temporary stage и сразу
удаляет buffer. Source и target применяют initial attempt + пять retries только
для admission `OperationalError`; batch retries не продолжают потерянную
target-транзакцию, а вызывают rollback без partial target state.

## Performance и source controls до DDL

Горизонт BR-003 на 2026-08-27: `[2025-01-01, 2026-08-28)`. Exact extract на
sample `[2026-07-01, 2026-08-01)` дал 45 705 строк за 947.491 ms,
317 758 shared-hit и 3 722 read blocks. Full exact plan после sample дал
1 206 620 строк за 8 604.852 ms, 3 824 482 shared-hit, 0 read и 21 862 temp
read blocks; один месячный buffer остаётся выбранным bounded размером.

Первый independent control был переписан до transport: коррелированная форма
на sample читала 2 772 089 shared-hit blocks за 1 523.589 ms. Reviewed
branch-map aggregate сохранил те же sample values (45 705 строк/ключей,
`-162646.00`, 102 legacy-excluded branch paths), но снизил sample до
137 396 shared-hit blocks и 256.743 ms; full plan — 6 713.238 ms. Full
source control, снятый до target work, дал 1 206 590 строк и ключей,
`584565.00`, диапазон `2025-01-01 05:00:01`—`2026-08-27 22:00:00`,
3 459 legacy-excluded branch paths. Это live-source observation; loader
сверяет target только с новым control того же exported snapshot.

Full contract control exact extract: required-null rows = 0, invalid
`record_kind` rows = 0; display nullable fields также без null. State control
base: `Active=false = 0`, null key references = 0. Значения не становятся
новым state-filter: first release сохраняет current M.

## Критерий закрытия

Нулевая разница source/stage/target independent controls, contract/key/null/
horizon/future-date/as-of checks, measured source and target plans, successful
atomic rerun и отсутствие изменения Power BI.
