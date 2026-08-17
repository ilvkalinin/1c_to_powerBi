# Серверная валидация источника — 2026-08-14

Этап: `STAGE_2_SERVER_VALIDATION`.

Все результаты получены одним `REPEATABLE READ, READ ONLY` снимком VM-1 с
`statement_timeout = 60s`. Горизонт BR-003 на дату проверки:
`[2025-01-01, 2027-01-01)`. Изменений в 1С и VM-2 не выполнялось.

## SV-LS-001 — `mart.lesson_room_slot_5m`

Выполненный SQL: [lesson_room_slot_5m_2026-08-14.sql](validation_sql/lesson_room_slot_5m_2026-08-14.sql).

| Контроль | Ожидание | Фактический результат | Статус |
|---|---|---|---|
| LS5-V01 | нужные поля двух документов и `InfoRg7107` существуют с точными типами | ID и ссылки — `bytea`, границы и дата создания — `timestamp without time zone`, состояния — `boolean`, минуты дежурства — `numeric`; все 29 полей `NOT NULL` | VALIDATED |
| LS5-V02 | одна строка на документ до слотов | ГЗ: 187 439 ID без повторов; ПЗ: 384 044 ID без повторов. Пустых границ и ключевых ссылок нет | VALIDATED |
| LS5-V03 | точные интервалы `[start,end)` разворачиваются в 5-минутные слоты без выхода и повторов | корректные ГЗ: 187 295 занятий / 1 964 875 слотов; ПЗ: 383 333 / 3 445 477. В контрольной неделе 2026-08-01—08 фактические и ожидаемые слоты совпали: ГЗ 22 134, ПЗ 29 994; outside/duplicates = 0 | VALIDATED |
| LS5-V04 | joins к измерениям не умножают урок | повторов после всех joins = 0. Club orphan = 0; orphan room/employee/service/activity/format сохранены наблюдением, без fallback | VALIDATED WITH NULL RISK |
| LS5-V05 | дежурства не становятся строками слот-факта без согласованного правила | 45 737 дежурств; пустых границ, клуба, сотрудника и помещения = 0. Эта ветвь не входит в согласованный контракт: финальный набор расписания исключает синтетическую услугу «Дежурство» | VALIDATED EXCLUDED |
| LS5-V06 | branch-specific payment и lateness не унифицируются | ГЗ: 99 960 club-time и 87 479 paid; ПЗ: 41 011 club-time, 337 577 paid, 5 456 reserve. Поздние: 1 720 ГЗ и 82 551 ПЗ | VALIDATED |

### Граничные интервалы

Ни одна строка не округлялась и не исключалась скрыто. В квалифицированных
ветвях есть 2 неположительных и 142 некратных пяти минутам ГЗ-интервала,
а также 711 некратных ПЗ-интервалов. `InfoRg7107` содержит 8 617 некратных
интервалов, но не является строковой ветвью этого mart.

Для записи строго пятиминутного факта невозможно одновременно сохранить
точный исходный конец такого интервала и представить его только полными
пятиминутными строками. Пользователь утвердил BR-021: положительные неполные
интервалы расширяются вправо до полного последнего слота; два неположительных
интервала не создают слот и остаются отдельным source control.

### Критичный артефакт для возможной доработки

Согласованный source rule `mart.group_lesson` исключает special-service ИП.
На live snapshot точное сравнение `decode('bcd000505688c8b011ee0a8ba155d4a1','hex')`
даёт 113 802 таких строки и 187 439 остальных. В существующем
`sql/marts/group_lesson_source_extract.sql` литерал содержит лишний обратный
слеш; его байты не равны согласованному ID. Поэтому текущий источник loader
даёт 301 241 строку, а уже загруженная `mart.group_lesson` содержит 301 237.

Это зафиксировано как критичный артефакт возможной доработки. Он не меняет
текущий объект, его refresh или результат первого релиза без отдельного
решения пользователя по BR-018 и отдельного DML-разрешения.

## SV-093 — «Загрузка ОП»: завершение bounded CRM controls

Статус: `VALIDATED` на live `gymdb` в одном `REPEATABLE READ, READ ONLY`
снимке 2026-08-14. Выполненный SQL:
[sales_interactions_global_review_2026-08-14.sql](validation_sql/sales_interactions_global_review_2026-08-14.sql).
Проверка идёт от трёх подтверждённых воронок к взаимодействиям через indexed
task-owner path, а не сканирует весь `Reference67` в порядке первичного ключа.

| Контроль | Фактический результат | Статус |
|---|---|---|
| SA-V02 | 100 interactions; 41 phone rows = 41 non-null technical phone keys; 1 interaction has two phone rows, max 2 | VALIDATED — phone rows сохраняются, `LEFT JOIN` null-placeholder не считается ключом |
| SA-V03 | 58 interactions have qualifying employment; 33 have one match, 25 have 2–3, 42 have none | VALIDATED — current `EXISTS` не размножает interaction; name-based rule не заменяется на ID |
| SA-V04 | 2 591 535 interactions in 2026; `marked = 0` | VALIDATED observation — новый state filter не вводится |

Прежний SA-V02 считал `ROW(NULL,NULL)` от `LEFT JOIN` как отдельный distinct
key и поэтому возвращал 101 technical key при 41 phone rows. Это дефект
контрольной метрики, не логики отчёта; он сохранён как артефакт возможной
доработки. В новом control null-placeholder явно исключён.

## SV-094 — «Поступления» и «Членство для правления»: физический ключ платежа

Статус: `VALIDATION_FAILED` для физического ключа ежемесячного рекаррингового
платежа; read-only SQL:
[membership_keys_global_review_2026-08-14.sql](validation_sql/membership_keys_global_review_2026-08-14.sql).

| Контроль | Фактический результат | Вывод |
|---|---|---|
| Technical movement keys | В обоих регистрах уникальные индексы `(RecorderTRef, RecorderRRef, LineNo)`; за BR-003 нет пустых ключей или сумм | движение имеет доказанный ключ |
| States/signs | `7370`: active `RecordKind 0/1` — 588 948/2 027 107, inactive — 10 462/35 967; `7739`: active `0/1` — 1 367 295/897 340 | это наблюдение, не основание менять current sign/filter rule |
| `contract × analytics_sequence` | 307 517 candidates; `NULL=0`; 274 296 duplicate groups; максимум 119 843 движений | отклонён как payment key |
| `contract × recorder` | 2 106 082 candidates; 337 638 duplicate groups; максимум 35 967 движений | отклонён как payment key |

BR-016 требует считать рекарринг одной ежемесячной payment unit, однако
физического идентификатора этой unit среди подтверждённых полей нет. Нельзя
схлопнуть такие группы `MIN`, `MAX` или `DISTINCT` без нового согласованного
правила. Денежное движение остаётся реализуемым с собственным ключом, а обе
контрактные KPI-витрины блокируются ровно на этой единице.

### Исправление SV-094 — 2026-08-17

Вывод SV-094 о блокере отозван. В исходном PBIT текущий M получает
`Текст после разделителя` из `АналитикаУчета`, а DAX `Кол Факт` создаёт одну
KPI-единицу на `Контракт × Текст после разделителя`, суммируя все движения
такой группы. Поэтому 274 296 многорядных групп в контрольном запросе —
ожидаемая структура платежа, а не дубликаты платежей. Период не выводится из
даты движения. Исходный SQL и его числа сохранены как критичный артефакт;
ошибочной была только интерпретация уникальности.

Статус после исправления: `VALIDATED — SV-096`.

## SV-095 — «Продажа детских пакетов»: line-to-line price/product

Статус: `VALIDATION_FAILED` для полного line-to-line покрытия. В
`Document346.VT4913` ключ строки `_fld4917` обязателен и имеет тип `bytea`;
`VT4924._fld4929` того же типа, а product/amount обязательны. По точному
`receipt_id + line_key` получено 46 797 строк пакетов: 46 759 имеют ровно одну
строку цены/номенклатуры, 38 не имеют ни одной, повторов нет. Для этих 38
строк fallback `AccumRg7739` по чек × взрослый контракт × ребёнок не дал ни
одного совпадения.

Текущий `LIMIT 1` не является допустимым fallback: он не создаёт отсутствующую
строку цены. Пользователь 2026-08-17 утвердил явное правило покрытия: для этих
38 строк `product_id = '0'`, `product_name = '0'`, `package_amount = 0`.
Источник для остальных строк не меняется. Исходный gap сохранён как артефакт
возможной методической доработки; правило возврата этим решением не меняется.

## SV-097 — «Новички и гостевые визиты»: bounded path and date controls

Статус: `PARTIALLY VALIDATED`. Read-only SQL:
[newcomer_guest_visits_global_review_2026-08-17.sql](validation_sql/newcomer_guest_visits_global_review_2026-08-17.sql).

| Контроль | Ожидание | Фактический результат | Статус |
|---|---|---|---|
| NVG-V02 | в bounded current document path нет отсутствующего документа/контракта и расхождения клиента | 100 июльских документов → 100 движений = 100 technical keys; без документа/движения, `NULL` контракта и mismatch клиента — 0 | VALIDATED bounded physical path |
| NVG-V06 | наблюдать физические даты для правила `[0,44]`, не создавая новый eligible-contract filter | 100 гостевых строк → 12 кандидатов на 0–45 дней; lag 0 = 6, lag 44 = 0, lag 45 = 0, вне окна = 0 | OBSERVED; границы 44/45 не доказаны этой выборкой |

Точный PBI-артефакт со списком 12 ACCUNIQ-услуг и выбором записи не найден в
проекте. Поэтому NV-V05/NV-V09 и полная сверка NVG-V06 остаются `BLOCKED`:
подбор услуг по именам или подстановка нового фильтра запрещены.

## SV-098 — «Отчёт по обращениям»: CRM core and comment controls

Статус: `PARTIALLY VALIDATED`. Read-only SQL:
[calls_report_global_review_2026-08-17.sql](validation_sql/calls_report_global_review_2026-08-17.sql).
Каждый запрос запускался отдельно с ограничением 20–30 секунд; поэтому
полногодовые числа — снимки изменяющегося источника, а не единый баланс.

| Контроль | Фактический результат | Статус |
|---|---|---|
| CR-V02 | В раннем снимке 59 380 feedback rows = 59 380 physical interaction IDs; duplicates, orphan task, `NULL`/future creation = 0 | VALIDATED physical core |
| CR-V03 | Phone rows и non-null phone technical keys = 0; HTML rows = 105 276, в 38 799 interactions больше одного HTML, максимум 15 | VALIDATED multiplicity observation — текущую агрегацию HTML нельзя убрать |
| CR-V04 | В следующем live-снимке 59 384 joined rows = 59 384 interaction IDs; dimension excess, missing task/funnel = 0; missing club = 1, client = 4 | VALIDATED WITH NULL RISK — unmatched dimensions не фильтруются |
| CR-V06 | Bounded 100-row control: no follow-up = 11; earlier follow-up = 0; same-timestamp ties = 0 | VALIDATED bounded ordering of current task-owner path |
| CR-V07 | Bounded 100-row control: 41 interactions have >1 post-creation comment, pre-creation and timestamp ties = 0, max = 6 | VALIDATED bounded comment ordering; `MIN` current aggregation materially needed |
| CR-V09 | Next live-snapshot: 59 385 feedback rows; marked = 0, archived = 34 330, future = 1 | OBSERVED — no state/date filter is added |

Первоначальная CR-V03 метрика из `calls_report_2026-08-12.sql` считала
`ROW(NULL,NULL)` от `LEFT JOIN` как один distinct phone key и давала 59 380
ложных keys при нуле phone rows. Это дефект контрольной метрики, не логики
отчёта; исходный запрос сохранён как критичный артефакт возможной доработки.
В SV-098 null-placeholder явно исключён.

Остаются `VALIDATION_PENDING`: точные GUID-наборы шести тем, speed/quality,
воронок и Jivo (CR-V05), полный business-grain знаменателя посещений
(CR-V08), независимая сверка с Power BI и rerun/refresh controls. Эти
проверки не подменяются наблюдениями SV-098.

## SV-099 — «Посещаемость клиентов с долгами»: movement and branch controls

Статус: `PARTIALLY VALIDATED`. Read-only SQL:
[visits_debt_global_review_2026-08-17.sql](validation_sql/visits_debt_global_review_2026-08-17.sql).

| Контроль | Фактический результат | Статус |
|---|---|---|
| DV-V01 | 482 347 movements за 2026 = столько же technical keys; inactive, null client/prebooking и null quantity/amount = 0 | VALIDATED physical movement key |
| DV-V04 | 236 274 client × prebooking pairs; 24 208 prebookings относятся к >1 клиенту, максимум 56; 233 733 пары имеют несколько движений | VALIDATED — `prebooking_id` не является ключом клиента; as-of key остаётся парой |
| DV-V02 | Current DAX classes `RecordKind 0/1 × quantity ±1` есть; вне этих четырёх классов 1 970 movements | VALIDATED observation / DECISION_REQUIRED — новое значение им не назначается |
| DV-V03 | После text-cast observation: 457 556 base rows, 456 639 current branch rows и keys; branch excess = 0, не выведено 917 | VALIDATED WITH ROW-LOSS RISK — current inner branch не меняется |
| DV-V06 | Source-side cast observation текстового visit filter: 35 rows = 35 technical keys, 32 client-day-club, missing/mismatched club = 0 | BLOCKED as cohort evidence — результат не подтверждает Power Query classification |

Старый DV-V03/DV-V06 SQL напрямую применял `ILIKE` к 1С-типу `mvarchar` и
не выполняется в PostgreSQL (`operator does not exist: mvarchar !~~* unknown`).
`::text` в SV-099 нужен только для безопасного read-only наблюдения; он не
заменяет current Power Query и не создаёт стабильный filter. Оригинальный SQL
сохранён как критичный артефакт возможной доработки.

До готовности отчёта остаются: подтверждённый ключ классификации посещения
вместо имени, правило для quantity `other`, независимые as-of controls на
контрольных датах из Power BI и rerun/SLA. Никакая из этих границ не закрыта
догадкой или новым фильтром.

## SV-100 — «Карта администратора»: Gymmy bounded controls

Статус: `PARTIALLY VALIDATED`. Внешний журнал администраторов не открывался:
Excel и Power Query остаются вне scope. Выполненный read-only SQL:
[administrator_card_global_review_2026-08-17.sql](validation_sql/administrator_card_global_review_2026-08-17.sql).

В июле 2026 точный список 12 карт и двух event GUID дал 9 082 Gymmy-события:
использовались 9 карт, присутствовали оба направления, `success = false` и
`NULL success` = 0. Физический ключ `(Period, Terminal, Client, EventID)`
подтверждён уникальным индексом `_inforg5836_1`; у всех 12 карт есть непустая
текстовая метка клуба. Поэтому исключение неуспешных событий осуществимо как
`success IS NOT FALSE`, а дневная агрегация не требует передачи сырых событий.

Текстовая метка, полученная из последнего слова описания карты, не стала
каноническим `club_id`: физическое соответствие 12 карт общему справочнику
клубов и независимая сверка дневных чисел с Power BI остаются
`VALIDATION_PENDING`. Никакие Excel-артефакты для этого не запрашивались и не
использовались.

## SV-101 — «Маркетинговая воронка»: task code in report scope

Статус: `PARTIALLY VALIDATED`. Read-only SQL:
[marketing_funnel_global_review_2026-08-17.sql](validation_sql/marketing_funnel_global_review_2026-08-17.sql).
В единственной воронке отчёта «Продажа клубной карты» 1 382 845 task rows =
1 382 845 physical task IDs = 1 382 845 codes; `NULL`/duplicate code = 0.
Следовательно, current DAX distinct по коду воспроизводим в этом scope.

Физическая связь с `InfoRg6798` остаётся по task ID (`Fld6799RRef`), а не по
отображаемому коду. Полный all-CRM aggregate намеренно не продолжался после
30-second limit: он не требуется для отчётного scope. CRM joins, states,
накопленный трафик, Power BI reconciliation и SLA остаются
`VALIDATION_PENDING`.
