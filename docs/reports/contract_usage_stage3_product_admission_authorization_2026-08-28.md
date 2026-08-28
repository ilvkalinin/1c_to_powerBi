# Авторизация product admission: `mart.contract_usage`

- Дата: 2026-08-28
- Пакет: `contract_usage_stage3_product_admission_2026-08-28`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёт: № 17 «Отчёт по %Renew» (`renew_contract_usage`)
- Основание: пользователь согласовал полный путь витрины с тестами и
  оптимизацией после corrected technical plan CU-TR-002.

## Неизменяемый scope

Источник — dynamic BR-003 horizon: январь--март — текущий и два предыдущих
года, апрель--декабрь — текущий и предыдущий; exclusive end — завтра по
Москве. В действительном membership-domain применяется повторно используемый
BR-047 predicate `Reference59.Fld672::date > Reference59.Fld671::date`;
исключённые строки не изменяют источник 1С. Сохраняются current-M joins,
`COUNT(*)`, `Reference59.Fld693`, grain «один контракт» и все колонки reviewed
mapping. Выполнить по порядку:

1. read-only source/target preflight, CU-S01--CU-S04 и actual-plan ladder
   1/2/3/6 месяцев, затем один full-range plan без параллельного transport;
2. выбрать только измеренный transport cap и зафиксировать отсутствие либо
   наличие обоснованной оптимизации. Сначала выполнить source-only measurement
   в ограниченном derived buffer без открытия target, затем вывести execution
   cap из фактических байтов; не изменять индексы или настройки 1С.
   Допустим только measured inline-CTE variant exact extract;
3. initial `CREATE SCHEMA IF NOT EXISTS mart` / `CREATE TABLE
   mart.contract_usage`, source-first derived binary COPY, advisory lock,
   temporary stage, full atomic replace, CU-R01--CU-R08 до `COMMIT`;
4. target read plan/size, contract checks и отдельный atomic rerun с fresh
   source snapshot и собственными expected controls.

Используются ровно reviewed artifacts: mapping, ADR-0006, data contract,
`contract_usage_source_extract.sql`, `contract_usage_source_controls.sql`,
`contract_usage_ddl.sql`, `load_contract_usage.py` и
`contract_usage_reconciliation.sql`.

## Границы, rollback и закрытие

Power BI/M/DAX и внешние Excel-артефакты не меняются и не анализируются.
Источник 1С остаётся read-only; не создаются source indexes или raw replicas.
Для устойчивости VPN один `REPEATABLE READ, READ ONLY` anchor экспортирует
snapshot; каждый independent control и extract открывает отдельный короткий
reader того же snapshot. Anchor не открывает target и не переносит raw-данные.
Каждый target DDL/load/rebuild идёт в одной transaction-scoped advisory-locked
транзакции; ошибка до commit откатывает target. Full rebuild фиксируется только
как measured baseline, не incremental SLA.

Пакет закрывается, когда full-window controls, source plan, transport cap,
initial load reconciliation, rerun reconciliation, target read plan и contract
checks записаны в execution evidence без отклонений; либо когда конкретный
измеренный control/connection показывает `BLOCKED`/`VALIDATION_FAILED` и target
сохраняет согласованное состояние.
