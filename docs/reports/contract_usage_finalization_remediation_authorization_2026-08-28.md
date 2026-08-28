# Авторизация remediation technical plan: `mart.contract_usage`

- Дата: 2026-08-28
- Пакет: `contract_usage_finalization_remediation_2026-08-28`
- Этап: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Отчёт: № 17 «Отчёт по %Renew» (`renew_contract_usage`)
- Основание: пользователь явно подтвердил удаление неподтверждённой
  finalization-механики.

## Разрешённый scope

Удалить только введённые без подтверждённого требования `is_finalized`,
`finalized_month`, `mutable_from_month`, cutoff/blocker и mutable-only replace
из mapping, data contract, ADR, DDL, source extract, runner, reconciliation,
catalogue и technical-review evidence. Перевести runner на полный atomic
rebuild exact current-M output: source-first temporary derived file, advisory
lock, target stage, atomic replace, reconciliation and rollback.

Сохранить без изменений fixed legacy window, current joins, `COUNT(*)`,
`Fld693`, grain «один контракт с current-M visits», source controls и границу
Power BI/Excel. Выполнить только read-only plan check точного revised extract.

## Границы и критерий закрытия

Пакет не выполняет target connection, DDL, DML, `COPY`, full-range transport,
Power BI/M/DAX change, анализ Excel/Power Query или изменение 1С.
Критерий закрытия: reviewed local set больше не содержит finalization policy;
full atomic rebuild/rollback/reconciliation определены; revised short actual
plan сохранён; VM-2 не изменялась.
