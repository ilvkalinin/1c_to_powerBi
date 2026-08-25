# S3-CBD-REFRESH-001: current full refresh `mart.client_base_daily`

Дата согласования: 2026-08-20. Статус: `COMPLETED`.

Пользователь подтвердил пакет, первоначально предложенный как первичная
загрузка `mart.client_base_daily`. Read-only preflight установил, что таблица
уже содержит historical baseline от 2026-08-19, поэтому во избежание
дублирования пакет выполняет ровно один current full refresh того же
существующего объекта. Это не создаёт новую витрину и не меняет business rule.

## Доказанный trigger

На горизонте BR-003 `[2025-01-01, 2027-01-01)` текущий source snapshot имеет
1 460 daily scope controls; с target расходятся 432. Следовательно, target
требует current refresh, а не повторной «первичной загрузки».

## Scope

1. Использовать без изменений reviewed source extract
   `sql/marts/client_base_daily_extract.sql`, независимые source controls
   `sql/marts/client_base_daily_source_controls.sql` и atomic replacement
   `sql/marts/client_base_daily_target_replace.sql` через
   `scripts/load_client_base_daily.py --apply`.
2. До `DELETE` проверить stage keys, scope, `NULL`, age/gender contract и
   равенство 1 460 source/day/scope controls; после replacement подтвердить
   те же controls target. Выполнить один rerun.
3. Разрешён только DML существующей `mart.client_base_daily`. Нет DDL, новых
   колонок, Power BI, Excel, scheduler, `snapshot`/`retention`, source write
   или ежедневного incremental refresh.

## Критерий закрытия

Атомарный current refresh имеет точное равенство source/stage/target daily
scope controls, ноль дубликатов и нарушений контракта; повторная валидация
подтверждает, что не опубликованы частичные данные. Длительность полной
пересборки фиксируется как baseline, но не как ежедневный SLA.

## Результат

Успешный atomic refresh завершился за `121.535` с на source snapshot:

| scope | Source/target `client_count` | Target rows |
|---|---:|---:|
| `club` | 58 974 520 | 1 520 294 |
| `network` | 58 916 918 | 137 059 |

До `DELETE` прошли все 1 460 day/scope controls и stage contract. После
`COMMIT` independent target reconciliation установила: 1 657 353 строки,
`duplicate_keys = 0`, `contract_violations = 0`,
`rows_outside_horizon = 0`.

Повторный запуск получил отдельный живой source snapshot и успешно прошёл
source transfer и stage controls; его target-соединение завершилось до
`COMMIT`. Проверка persisted target показала сохранение предыдущего полностью
согласованного snapshot, то есть частичный replacement не опубликован.
Пользователь подтвердил, что для живой базы не требуется немедленно
пересобирать факт ради единичных изменений; повторные full rebuild в этом
пакете остановлены. Будущий ежедневный incremental refresh остаётся отдельным
проектом после готовности всех витрин.
