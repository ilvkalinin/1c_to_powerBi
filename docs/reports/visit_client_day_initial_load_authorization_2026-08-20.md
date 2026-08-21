# S3-VISIT-CLIENT-DAY-001: initial load `mart.visit_client_day`

Дата: 2026-08-20. Статус: `CLOSED 2026-08-21`.

Пользователь явно подтвердил единый пакет для новой базовой витрины
`mart.visit_client_day`. Точный SQL перед запуском отдельно не запрашивается:
пользователь ранее разрешил применять подтверждённую логику из mapping/ADR без
повторного показа SQL.

## Scope

- создать только `mart.visit_client_day` по ADR-0003 и утверждённому mapping;
- source-side read-only extract и атомарная initial BR-003 загрузка;
- source → target COPY row reconciliation, key/flag/row controls, rerun и
  измерение полного refresh;
- обновить mapping, data contract, каталог продуктов и checkpoint.

## Границы

Не входят: Power BI, расписание, инкрементальная стратегия, `mart.club_day_metrics`,
справочники, raw-копии источников, другие витрины, изменение 1С и внешние файлы.
Источник 1С остаётся read-only. Любая ошибка до COMMIT откатывает target DML;
после COMMIT rollback отдельным пакетом не автоматизируется.

## Критерий закрытия

Одна физическая таблица имеет подтверждённые grain/key/contract; source-to-target
COPY row controls и target controls совпадают; duplicate/contract violations равны нулю; повторный
атомарный rebuild проходит без изменения методики; зафиксировано фактическое
время полного BR-003 refresh.

## DQ-VC-002: independent-fact boundary control

Дата: 2026-08-20. Среда: read-only источник, первый блок
`2025-01-01…2025-07-01`. Первоначальная гипотеза проверяла, являются ли
купоны и ДПФУ подмножеством базового `AccumRg7575 → Document325` на
`(date, actual club, client)`.

Фактический результат: coupon `7 863 / 17 outside`; ДПФУ
`149 338 / 28 492 outside`. Для купона ни один внешний ключ не имел того же
клиента в базовом наборе периода. Для ДПФУ 26 467 внешних ключей имели того же
клиента и фактический клуб в другую дату, 1 337 — того же клиента в ту же дату,
а 26 890 — того же клиента где-либо в базовом наборе.

Статус: `VALIDATED — independent facts`, 2026-08-21. Актуальные PBIT обоих
отчётов подтверждают, что купон и ДПФУ загружаются отдельными таблицами,
считаются отдельными DAX-мерами и не должны становиться флагами базового
client-day. Обычные и Пушкинские категории остаются одной агрегацией.

## DQ-VC-003: base plus Pushkinsky merge equivalence

Дата: 2026-08-20. Среда: read-only источник, первый блок
`2025-01-01…2025-07-01`. Ожидание: после замены двух веток — базовое
посещение и Пушкинский — одной агрегацией `date × actual club × client`,
набор строк и девять флагов не меняются.

Фактический результат: old rows `2 323 127`, new rows `2 323 127`,
old-only `0`, new-only `0`; wall time контрольной сверки `68.469 с`.
Статус: `PASS`. Это сравнение не измеряет SLA: оно параллельно выполняет
старую и новую логику для доказательства эквивалентности.

## Граница условных показателей

Проверка PBIT 2026-08-21 подтвердила: посещения клуба, ДПФУ, купоны и ГП —
самостоятельные обезличенные факты. Они не сверяются по клиенту, количеству
строк или кратности. «Без тренера» остаётся условной арифметической
DAX-мерой, а не классификацией строки посещения. `has_paid_service` и
`has_coupon` удалены из extract и target contract.

## DQ-VC-004: финальный H1 transport и target control

Дата: 2026-08-21. После PBIT-проверки extract содержит только базовое
посещение и Пушкинские флаги. Загрузка выполняется одной транзакцией:
`TRUNCATE mart.visit_client_day → COPY BINARY` с VM-1 в target; число строк
каждого source/target COPY-блока обязано совпасть до commit. Это не компрессия
и не изменяет значения.

Первый блок `2025-01-01…2025-07-01` закоммичен: `2 323 041` строк,
`has_visit 2 323 041`, member `111 499`, guest `2 186`, VIP `2 276`,
ДРЦ `1 263`, продлёнка `454`, Умняшки `0`, null ключей `0`; primary key
присутствует. Отличие 86 строк от более раннего read-only снимка объясняется
живым источником и не является отклонением внутри одной refresh-транзакции.
Статус: `PASS`.

## DQ-VC-005: full BR-003 initial load, rerun and acceptance controls

Дата: 2026-08-21. Горизонт обоих запусков: `[2025-01-01, 2027-01-01)`.
После одного незавершённого полугодового transport-прогона (первый H1-блок
прошёл, второй ожидал сокет без прогресса) его target-транзакция была откатана;
предыдущий закоммиченный H1-срез сохранён. Методика, extract и grain не
изменялись. Размер transport-блока стал параметром загрузчика; оба успешных
полных запуска использовали квартальные блоки в одной атомарной транзакции.

| Check | First full rebuild | Rerun | Status |
|---|---:|---:|---|
| Source → target COPY rows | 7,172,335 = 7,172,335 | 7,172,391 = 7,172,391 | PASS per block and total |
| `has_visit` | 7,172,335 | 7,172,391 | PASS |
| member / guest / VIP | 346,670 / 6,332 / 6,909 | 346,671 / 6,332 / 6,909 | PASS |
| ДРЦ / продлёнка / Умняшки | 3,911 / 626 / 306 | 3,911 / 626 / 306 | PASS |
| NULL contract fields / out-of-horizon rows | 0 / 0 | 0 / 0 | PASS |
| Full rebuild elapsed time | 320.152 s | 313.035 s | MEASURED; not a daily incremental SLA |

The 56-row and one-member-flag difference between runs is from two separate
repeatable-read snapshots of the live read-only source; each run reconciles
its own source COPY count to the target before `COMMIT`. Final target controls
are 7,172,391 rows, date range `2025-01-01…2026-08-21`, no contract nulls and
the physical primary key `(visit_date, club_id, client_key)`. No Power BI
switch, schedule, incremental strategy or source write was performed.
