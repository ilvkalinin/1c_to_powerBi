# Исполнение Stage 3: «Маркетинговая воронка»

Статус: `VALIDATED`.

## Attempt MF-LOAD-001

Запуск reviewed runner выполнил source `REPEATABLE READ READ ONLY` snapshot
для BR-003 horizon `[2025-01-01, 2027-01-01)`:

| Extract | Source COPY rows | Result |
|---|---:|---|
| `task` | 865 775 | получен |
| `task_contract` | 215 589 | получен |

`COPY` в `mart.marketing_funnel_task` прошёл, но `COPY` bridge был остановлен
PK `marketing_funnel_task_contract_pkey`: source extract содержит повтор
`(task_id, contract_id)`. Runner откатил всю target-транзакцию. Read-only
проверка после попытки подтверждает: обе целевые таблицы отсутствуют.

## Read-only diagnosis MF-DIAG-001—002

- `task_id` в task extract уникален: excess duplicate keys = `0`.
- В bridge extract: 215 589 строк, 215 570 уникальных пар, то есть 19
  лишних строк в 19 группах по две строки.
- Во всех 19 группах все девять неключевых полей совпадают, включая
  `activation_date`, `is_conversion_qualified` и `contract_count`.

Следовательно, это точные технические повторы уже утверждённого candidate
grain, а не альтернативные контрактные факты и не методическое расхождение.

## Safeguard MF-FIX-001

Добавлен reviewed `DISTINCT` на полный projected bridge row. Он эквивалентен
dedup уже утверждённой пары только для 19 подтверждённо идентичных source
повторов; не применяет global dedup по контракту и не меняет grain, BR-003,
BR-020, DDL или Power BI-границу. Новое source-to-target контрольное значение
bridge — 215 570 строк; initial load и один rerun остаются обязательными.

## Safeguard MF-FIX-002

MF-R05 then proved that an extract lower bound `activation_date >=
2024-01-01` omitted historic contract-client rows needed by the approved
current DAX accumulated-traffic measure. A read-only hypothetical control
with the bound removed and `activation_date IS NOT NULL` returned exactly
`66 404 - 27 319 - 15 221 = 23 864`. The reviewed extract now preserves that
history for every BR-003 task; BR-020 qualification and `contract_count`
remain unchanged. Initial load and rerun still remain required.

## Safeguard MF-FIX-003

The old `MF-R04` rejected every historic activation even though `MF-R05`
requires that history. It now checks the valid invariant: historic links must
never be BR-020-qualified or contribute `contract_count`; task BR-003 bounds
remain unchanged.

## Rerun interruption and telemetry MF-RUN-002

Initial load committed `865 812` task and `341 690` bridge rows with all six
controls passing. The mandatory rerun transferred 544 402 203 binary-COPY
bytes, then waited more than 26 minutes for VM-2 without a terminal server
response. `SIGINT` did not interrupt the libpq wait; `SIGTERM` closed only the
runner process and its uncommitted rerun transaction. Read-only verification
confirmed the initial snapshot remains intact at `865 812 / 341 690`.

The runner now emits non-sensitive target stage markers. The next allowed
rerun will identify whether any wait occurs at lock, delete, either COPY, a
specific reconciliation control or commit; no business SQL changed.

## Successful initial load and rerun MF-LOAD-002—003

Initial atomic load committed a BR-003 snapshot of `865 812` task and
`341 690` bridge rows after `MF-R01`—`MF-R06 = PASS`.

The instrumented mandatory rerun took a fresh source snapshot of `865 891`
task and `341 704` bridge rows. VM-2 acquired the lock, completed child-first
delete, copied `430 264 473` task bytes and `114 176 541` bridge bytes, then
completed each `MF-R01`—`MF-R06` and committed. The small difference between
snapshots is recorded as a live-source change; every source-to-target control
within each snapshot had zero deviation. The rerun is a full rebuild and no
daily incremental SLA is claimed.
