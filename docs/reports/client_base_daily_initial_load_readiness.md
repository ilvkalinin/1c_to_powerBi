# S3-CBD-LOAD-REVIEW-001: готовность начальной загрузки `mart.client_base_daily`

Дата: 2026-08-19. Статус: `REVIEWED / TARGET DML NOT YET APPROVED`.

Пакет не выполнил DML. Источник VM-1 читался только в `REPEATABLE READ,
READ ONLY`; целевая VM-2 проверялась только чтением. Power BI, расписание,
`client_base_snapshot` и `client_base_retention` не менялись.

## Подтверждённый запуск

Горизонт BR-003: `[2025-01-01, 2027-01-01)`. Extract сохраняет точное
условие BR-005: абонемент входит в снимок даты D только когда
`active_from < D` и `active_to >= D - 1`. Для `club` клиент считается в
каждом клубе отдельно, для `network` — один раз по сети. Возраст меняется
только на дне рождения; sentinel `0001-01-01` и неизвестный пол становятся
`Не указано` по подтверждённому контракту.

На VM-1 остаются ID клиента и абонемента. На VM-2 передаются только семь
агрегированных контрактных полей.

## Read-only evidence

| Check | Ожидание | Факт | Статус |
|---|---|---|---|
| `CBD-LOAD-PRE-001` | целевая схема: 7 колонок, 5 ключей/checks, 5 `NOT NULL`, 0 строк | все четыре условия `true` | PASS |
| `CBD-LOAD-SRC-001` | по одной положительной сумме на день и scope: 730 × 2 | 1 460 из 1 460; club 50 969–92 918, network 50 955–92 826 | PASS |
| `CBD-LOAD-SRC-002` | aggregate extract равен независимому interval-control по каждому дню/scope | 1 460 expected = 1 460 actual; расхождений 0 | PASS |
| `CBD-LOAD-PERF-001` | extract не требует DML и имеет измеримое source-side время | 1 657 346 агрегированных строк; source reconciliation extract 14,781 с в одном snapshot | MEASURED, не SLA |

Ранее прямой client-day extract упёрся в 30-секундный лимит. Reviewed extract
заменяет только технический способ вычисления: объединяет интервалы действия
абонементов, режет их на возрастные отрезки и разворачивает только постоянные
итоговые интервалы. `CBD-LOAD-SRC-002` подтверждает, что это не изменило
дневные totals обоих scope.

## Точный DML-контур

[`client_base_daily_initial_load_review.sql`](client_base_daily_initial_load_review.sql)
показывает всю transaction на VM-2. Исполнитель
[`scripts/load_client_base_daily.py`](../../scripts/load_client_base_daily.py)
не делает записей без `--apply` и до `DELETE` обязан проверить:

1. логический ключ, horizon и все ограничения stage;
2. равенство stage с независимыми source totals по каждому дню и scope;
3. равенство записанной таблицы с тем же source snapshot перед `COMMIT`.

Для бинарной передачи полного агрегата runner применяет к VM-1 жёсткий
60-секундный `statement_timeout`: прежний 30-секундный cap отменил COPY до
первого target `DELETE`, хотя сам source extract был измерен в пределах этого
cap. Это технический лимит передачи, а не изменение source rule, horizon или
результата.

При любой ошибке transaction откатывается. После `COMMIT` отдельными задачами
остаются rerun, измерение end-to-end SLA и переключение Power BI.
