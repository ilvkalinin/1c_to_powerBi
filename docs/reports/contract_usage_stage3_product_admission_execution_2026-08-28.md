# Product-admission execution: `mart.contract_usage`

Статус: `VALIDATED — CU-LOAD-001—008`.

Пакет `contract_usage_stage3_product_admission_2026-08-28` выполнен для
`renew_contract_usage`. Power BI, M, DAX и внешние Excel-артефакты не менялись
по BR-036. Источник 1С оставался read-only.

## Граница и правило допуска

На момент выполнения московская дата — 2026-08-28, поэтому dynamic BR-003
horizon был `[2025-01-01, 2026-08-29)`: текущий день допустим, будущие visit
facts запрещены CU-S04. В membership-domain применён повторно используемый
BR-047 predicate `Reference59.Fld672::date > Reference59.Fld671::date`.
Нулевая или обратная длительность не загружается в target; источник 1С не
изменяется.

## Source performance и transport

`EXPLAIN (ANALYZE, BUFFERS)` exact extract выполнен последовательно, без
параллельного transport:

| Horizon | Rows | Execution | Shared hit/read | Temp read/written |
|---|---:|---:|---:|---:|
| 2026-07-01..2026-08-01 | 51,383 | 5,642.848 ms | 3,427,789 / 179 | 7,069 / 7,069 |
| 2026-05-01..2026-08-01 | 77,169 | 8,587.386 ms | 7,353,932 / 0 | 9,728 / 9,728 |
| 2026-02-01..2026-08-01 | 102,816 | 17,551.994 ms | 15,448,741 / 0 | 14,356 / 14,356 |
| 2025-01-01..2026-08-29 | 218,371 | 44,984.596 ms | 47,973,219 / 0 | 33,034 / 33,034 |

Ни source index, ни server/planner setting не менялись. Source-only measurement
в exported `REPEATABLE READ, READ ONLY` snapshot прошёл CU-S01--CU-S04:
218,371 contract rows, 7,223,505 visits и 33,363,633 derived binary-COPY
bytes. Временный проверочный cap 1 GiB не открыл target; для execution выбран
measured-safe cap 64 MiB. Temporary file содержит только target columns и
удаляется после каждой попытки.

Первый initial source reader был оборван VPN во время independent control;
target ещё не открывался и `to_regclass('mart.contract_usage')` оставался
`NULL`. Runner исправлен: на `OperationalError` он удаляет собственный
временный файл и максимум трижды перезапускает всю source-first работу в fresh
snapshot. Unit-check этого пути и retry-policy прошли; две доказанно
осиротевшие собственные source-сессии завершены без изменения данных.

## Initial load и reconciliation

Successful initial source snapshot: 218,375 rows, 7,223,555 visits,
`min(membership_start_date)=2015-01-01`,
`max(membership_end_date)=2300-05-21`, 33,364,245 bytes. В одной target
transaction под advisory lock выполнены `CREATE SCHEMA`, `CREATE TABLE`,
temporary stage, binary COPY, insert и CU-R01--CU-R08 до `COMMIT`; все controls
passed. Initial target contract checks: 0 invalid intervals, 0 invalid active
months, 0 nonpositive visit counts; target size 55,017,472 bytes.

## Atomic rerun и target acceptance

Fresh source snapshot rerun прошёл CU-S01--CU-S04 и CU-R01--CU-R08 со своими
expected controls: 218,376 rows, 7,223,594 visits, 33,364,437 bytes. Разница
от initial — изменение live source между независимыми snapshots, не target
deviation.

Final target checks: 218,376 rows, 7,223,594 visits,
`min(membership_start_date)=2015-01-01`,
`max(membership_end_date)=2300-05-21`, 0 strict interval violations, 0 invalid
active months и 0 nonpositive visit counts. После rerun
`pg_total_relation_size` = 98,697,216 bytes. Representative grouped target
read plan вернул 83 months за 90.933 ms (planning 0.295 ms), shared hit 7,376,
без shared read и temp I/O.

Это полный atomic rebuild baseline, не incremental refresh и не SLA. Power BI
остается вне пакета до общего разрешения по BR-036.
