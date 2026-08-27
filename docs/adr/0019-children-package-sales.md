# ADR-0019: продажи детских пакетов

- Статус: `IMPLEMENTED / VALIDATED — BR-039`
- Дата: 2026-08-27
- Отчёт: №15 «Продажа детских пакетов»

## Решение

Целевой объект — физическая таблица `mart.children_package_sale`. Её grain —
не произвольная строка `VT4913`, а distinct output переданного 1С-отчёта
`ПродажиДопПакетов.erf`, ограниченный current-Power-BI eligibility взрослого
абонемента и строками с ребёнком.

Возвраты повторяют source `CASE`: отрицательная `СтоимостьБезСкидки` движения
`AccumRg7646` создаёт «Расход» со знаковыми количеством и суммой. Связь
движения с child-package result происходит по `ДокументПродажи × Контрагент`;
`VT4913 → VT4924` использует только подтверждённый `КлючСтроки`. Это не
претендует на line-level attribution, поэтому BR-037 здесь не используется.

Логический ключ `report_row_id` — MD5 raw values final `DISTINCT` output. На
full control `[2025-01-01, 2026-08-28)` 19 412 child rows и 123 возврата на
−227 500, duplicate key = 0. Движение взрослого и product сохраняются как в
1С-отчёте: их подмена соответствующими значениями membership/stock меняет 4
и 54 строки соответственно.

Физическая таблица выбрана из-за раздельных VM и повторных сложных joins.
Универсальный sales fact, raw-реплика и постоянный staging не создаются.

## Power BI boundary

Для совместимости с current Power BI `club_id` остаётся основным клубом
доступа membership. Клуб продажи сохранён только технически, поскольку он
участвует в distinct output; 28 отсутствующих access-club names не исключают
source row. Power BI/M/DAX/connection не меняются в этом пакете по BR-036.

## Physical execution

Immutable extract, independent source control, DDL/load/reconciliation SQL и
месячный/full source plans reviewed. `2026-08-27` reviewed atomic rerun
replaced the target under an advisory lock: 19,412 rows, 11 zero-deviation
reconciliation controls and a 21.255 ms target read-plan. This is a measured
full-rebuild baseline, not an incremental SLA; Power BI remains unchanged by
BR-036. See the Stage 3 admission evidence for the execution log and values.

## Доказательства

- [mapping](../mappings/children_package_sales.md)
- [contract](../data_contracts/children_package_sales.md)
- [Stage 3 admission](../reports/children_package_sales_stage3_product_admission_2026-08-27.md)
- `sql/marts/children_package_sale_erf_source_control.sql`
- `sql/marts/children_package_sale_extract.sql`
- `sql/marts/children_package_sale_ddl.sql`
- `scripts/load_children_package_sale.py`
- `sql/tests/children_package_sale_reconciliation.sql`
