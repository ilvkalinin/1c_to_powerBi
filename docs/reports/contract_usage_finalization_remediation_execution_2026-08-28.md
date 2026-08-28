# Remediation technical review: `mart.contract_usage`

Статус: `CU-TR-002 CLOSED / PHYSICAL ADMISSION PENDING`.

## Причина и границы

Пользователь подтвердил удаление неподтверждённой finalization-механики из
нового technical plan. Этот пакет меняет только локальные technical artifacts
`mart.contract_usage`: mapping, data contract, ADR, exact extract, DDL,
future runner и reconciliation. Он сохраняет current-M fixed legacy window,
joins, `COUNT(*)`, `Reference59.Fld693` и grain «один контракт».

Power BI, внешние Excel-артефакты, VM-2 и 1С не изменялись. Target connection,
DDL/DML/COPY, полный transport, target reconciliation и Power BI switch не
выполнялись (`NOT_EXECUTED`).

## Исправленный delivery design

Future runner не имеет default source window или transfer cap. Physical package
должен передать `legacy_start`, `legacy_end` и `max_transfer_bytes`. Он:

1. выполняет CU-S01--CU-S03 в read-only source session;
2. записывает только derived target columns в capped temporary binary file;
3. после закрытия source session открывает target transaction, берёт advisory
   lock, загружает temporary stage и заменяет весь target через `DELETE` +
   `INSERT` в той же транзакции;
4. выполняет reconciliation до `COMMIT` и откатывает транзакцию при ошибке.

Это полный atomic rebuild, не incremental refresh и не заявка на ежедневный
SLA. Нет полей или cutoff, выделяющих неизменяемую либо mutable часть target.

## CU-TR-002: повторное actual-plan evidence

В fresh `REPEATABLE READ, READ ONLY` source session выполнен точный revised
extract для `[2026-08-17, 2026-08-24)`. План вернул 31,788 target-grain строк:

| Метрика | Значение |
|---|---:|
| Planning time | 7.249 ms |
| Execution time | 1,513.934 ms |
| Shared hit blocks | 1,060,822 |
| Shared read blocks | 0 |
| Temp read / written blocks | 0 / 0 |

Изменение вычисляемых output-колонок не дало измеримого основания менять
join order, session planner settings или предлагать source index. Это только
short-sample evidence; обязательны full-window CU-S01--CU-S03, measured
transfer cap и full-range plan в отдельном physical package.

## Статус следующей работы

Локальный набор согласован с corrected scope. Physical admission pending:
потребуется отдельное явное одобрение полного пакета с его source range,
full-window controls, measured source baseline, VM-2 DDL/load/reconciliation,
atomic rerun и target read-plan.

Локальная проверка syntax runner-а, connection-retry policy и `git diff --check`
прошла. Эти проверки не заменяют target execution.
