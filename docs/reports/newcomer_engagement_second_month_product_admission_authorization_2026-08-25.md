# Авторизация пакета: «Вовлечение новичков — второй месяц»

Статус: `ACTIVE — STAGE_3_PRODUCT_ADMISSION`.

## Подтверждённый scope

Пользователь 2026-08-25 подтвердил выполнение всех необходимых этапов для
отдельного продукта `mart.newcomer_engagement_second_month`: полный
source-to-target mapping и reuse-review, read-only source controls, immutable
DDL/extract/loader/reconciliation, initial DDL/load, independent
source-to-target reconciliation, measured full rebuild и atomic rerun.

## Граница и опасные операции

1С остаётся read-only. На VM-2 разрешён только компактный агрегированный факт;
raw-регистры и постоянный client-level staging запрещены. Power BI, PBIT, M,
DAX, Excel, подключения и refresh-настройки не изменяются по BR-036.

В scope разрешены `CREATE SCHEMA IF NOT EXISTS mart`, `CREATE TABLE
mart.newcomer_engagement_second_month`, temporary target staging, initial
`COPY`, а для rerun — transaction-scoped advisory lock, `DELETE` и `INSERT`
внутри одной target-транзакции. При любой ошибке target-транзакция откатывается;
автоматическое удаление объекта запрещено.

Детские пакеты включаются с `age_category = 'Дети'`. Их valid-sale/return
eligibility и выбор повторной даты продажи переиспользуют BR-037, что
пользователь явно распространил на этот факт 2026-08-25; это целевое правило
имеет приоритет над прежним PBIT-исходником второго месяца.

## Условие начала DDL

До DDL пакет обязан создать и проверить immutable implementation set: mapping,
ADR, data contract, source extract, DDL, loader, independent expected controls
и target reconciliation. В SQL не допускаются колонки с `UNKNOWN` lineage,
grain, типом либо NULL-policy.

Immutable implementation set reviewed in this package:

- [`mapping`](../mappings/newcomer_engagement_second_month.md),
  [`ADR-0009`](../adr/0009-newcomer-engagement-second-month.md) and
  [`data contract`](../data_contracts/newcomer_engagement_second_month.md);
- [`DDL`](../../sql/marts/newcomer_engagement_second_month_ddl.sql),
  [`source extract`](../../sql/marts/newcomer_engagement_second_month_extract.sql),
  [`atomic loader`](../../scripts/load_newcomer_engagement_second_month.py) and
  [`target reconciliation`](../../sql/tests/newcomer_engagement_second_month_reconciliation.sql).

First full BR-003 source control: 166 969 source rows, 166 969 business pairs,
769 453 register-row visits, no mandatory NULL and no duplicate source identity.

## Performance admission before transport

The exact extract was first measured on representative July 2026 sample
`[2026-07-01, 2026-08-01)`: 5 303 rows, planning 42.802 ms, execution
7 792.422 ms, 3 501 255 shared hits, 6 reads, temporary read/write
7 031/15 402 blocks. The subsequently measured full BR-003 baseline produced
166 969 rows in 47 805.658 ms (planning 44.014 ms; 30 343 177 hits; 12 345
reads; temp 26 036/107 649). The source extract is therefore admitted only as
a measured full rebuild; no incremental SLA or index is claimed. No concurrent
heavy source query runs during transport.

## Критерий закрытия

Для каждого initial run и rerun expected controls получаются отдельным
source-side путём в том же `REPEATABLE READ, READ ONLY` snapshot. Отклонения
source-to-target rows, business pairs, sums/counts, date horizon, key,
NULL/type/range, join/state/correction/deletion и access controls должны быть
нулевыми; source/target plans, размер, full-rebuild time и rerun должны быть
записаны. Power BI boundary остаётся `DEFERRED`.
