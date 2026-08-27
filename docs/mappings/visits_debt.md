# Source-to-target mapping: «Отчет по посещаемости клиентов с долгами»

Статус: `IMPLEMENTED / STAGE_3 PRODUCT ADMISSION VALIDATED — VD-LOAD-001 / Power BI unchanged`.

Для `mart.unconfirmed_service_debt_movement` выполнены DDL и atomic loader в
пакете `visits_debt_product_admission_2026-08-27`. Mapping описывает
два несовместимых по grain логических набора, которые не должны смешиваться.

## Stage 2 evidence — SV-089, SV-099

SV-002/SV-006 подтверждают физические relations current M; SV-008 —
физический `RecordKind` `_accumrg7509`; SV-013/SV-017 — PK-side cardinality
`_accumrg7575 → _document325` и reference dimensions основной visit-ветки.
Следовательно, `mart.visit_client_day` остаётся допустимым reuse только для
cohort, а `AccumRg7509` — отдельным movement fact. SV-099 подтвердил
уникальность ключа, отсутствие пустых ключевых ссылок и отсутствие branch
multiplication. `prebooking_id` не уникален по клиенту, поэтому as-of key
остаётся `client × prebooking`. Единая классификация посещения подтверждена
правилом BR-025; as-of компонент проверен DV-V05B. `quantity other`
воспроизводится current DAX: не участвует в `unconfirmed`, но остаётся в сумме
непогашенной группы.

[`SV-099 SQL`](../source_metadata/validation_sql/visits_debt_global_review_2026-08-17.sql)
выполнен read-only. Его полный результат и критичный артефакт `mvarchar` — в
[`server validation`](../source_metadata/server_validation_2026-08-14.md#sv-099--посещаемость-клиентов-с-долгами-movement-and-branch-controls).
Реализация не разрешена.

## 1. Логический набор движений долга по услуге

Гранулярность одной строки:

> одно движение регистра неподтверждённой услуги: `период × регистратор × номер строки`.

Физический ключ: `(debt_event_at, recorder_type, recorder_id, recorder_line_no)`.
`recorder_type` обязателен: без него `recorder_id` полиморфного 1С не образует
доказанный ключ. Бизнесовый as-of ключ: `client_key × prebooking_id`.

| Целевая колонка | Бизнес-описание | Источник / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `debt_event_at` | момент движения долга | `_accumrg7509._period` | без округления до момента as-of; день визуала = `::date` | `timestamp` | нет | CONFIRMED source | SV-099, VD-REC-007 |
| `recorder_type`, `recorder_id`, `recorder_line_no` | полный технический ключ движения | `_recordertref`, `_recorderrref`, `_lineno` | сохранить без source-side дедупликации | `bytea`, `bytea`, `integer` | нет | CONFIRMED source | SV-099, VD-REC-002 |
| `record_kind` | вид движения | `_recordkind` | сохранить исходный код `0/1`; DAX-классы определяются количеством | `smallint` | нет | CONFIRMED source | SV-099, VD-REC-007 |
| `client_key` | стабильный ключ cohort/as-of | `_fld7511rref` | защищённый стабильный ключ | `bytea` | нет | CONFIRMED source | DV-V05B, VD-REC-007 |
| `client_code`, `client_name` | отображаемый код и ФИО | `Reference141X1.Code`, `Description` | report-specific PII detail; доступен всем, у кого есть доступ к данному Power BI-отчёту | `text` | да | CONFIRMED — решение пользователя 2026-07-31 | DV-V04 |
| `club_id` | клуб услуги/долга | `_fld7510rref` | стабильный идентификатор, не имя | `bytea` | нет | CONFIRMED source | SV-099, VD-REC-007 |
| `prebooking_id` | предварительная/групповая запись, по которой возникает долг | `_fld7512_rrref` | сохранить до source-side aggregation | `bytea` | нет | CONFIRMED source | SV-099, VD-REC-007 |
| `service_id`, `service_name` | услуга долга и название в detail | `_fld7513rref`, `_reference163._description` | ID — всегда; имя — detail | `bytea`, `text` | ID нет, имя да | CONFIRMED current consumer | SV-099, VD-REC-007 |
| `employee_id`, `employee_name` | оказавший услугу сотрудник | `_document329._fld4322rref` / `_document279._fld3223rref` → `_reference225` | две сохранённые current-M ветки `UNION ALL` | `bytea`, `text` | ID нет, имя да | CONFIRMED source | SV-099, VD-REC-007 |
| `service_start_at`, `service_end_at` | время услуги | `_fld7514`, `_fld7515` | без замены на период движения | `timestamp` | нет | CONFIRMED source | VD-REC-007 |
| `quantity_delta` | вклад в статус неподтверждённой услуги | `_fld7516`, `_recordkind` | только `RecordKind × ±1` участвуют в DAX `unconfirmed`; другие quantity не меняют его, но их amount не исключается из суммы открытой группы | `numeric(10,0)` | нет | CONFIRMED current DAX | SV-099, VD-REC-007 |
| `amount_delta` | знаковая сумма движения | `_fld7517`, `_recordkind` | current M: `RecordKind = 1` умножить на `-1`, иначе оставить знак | `numeric(15,2)` | нет | CONFIRMED current calculation | SV-099, VD-REC-003 |

## 2. Когорта посетителей

Используется существующий кандидат общего факта `mart.visit_client_day`, только
если его `client_key` можно безопасно связать с controlled client detail. Факт
не расширяется PII-полями.

Гранулярность: дата фактического посещения × фактический клуб × стабильный клиент.

| Целевая колонка | Бизнес-описание | Источник / преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|
| `visit_date` | день включения клиента в когорту | `AccumRg7575.Period` / `Document325`; в cohort входят только `Document325.Fld4164RRef = 9a5a4c90d2b1aede4b91dcd1abe84c43` по BR-025 | `date` | нет | CONFIRMED user rule / source sample validated | BR-025, DV-V05B |
| `visit_club_id` | фактический клуб посещения | `Document325.Fld4167` после BR-025 | `bytea` | нет | CONFIRMED rule — BR-006/BR-025 | DV-V05B |
| `client_key` | клиент для пересечения с движениями долга | `Document325.Fld4171`; в DV-V05B совпал с `AccumRg7575.Fld7576` на двух датах × двух клубах | `bytea` | нет | CONFIRMED source sample | DV-V05B |
| `visit_client_count` | вклад уникального клиента в график посещений | `1` после client-day схлопывания | `smallint` | нет | CONFIRMED — решение пользователя 2026-07-31 | DV-V05 |

## Производные показатели Power BI

| Показатель | Правило | Граница PostgreSQL / Power BI | Статус |
|---|---|---|---|
| Долг на начало / конец дня | as-of сумма `amount_delta` только по открытым `client_key × prebooking_id`; границы `< D` / `<= D` | движения и ключи — PostgreSQL; cohort и filter-dependent as-of — DAX | CONFIRMED current |
| Погашено за день | пересечение долгов до `D` с ПЗ, закрытыми в `D` | DAX до подтверждения безопасной предагрегации | CONFIRMED current |
| Новые долги | текущая DAX-формула | DAX | CONFIRMED current |
| Количество клиентов с долгами | distinct `client_key` с положительным долгом на конец дня в когорте | DAX | CONFIRMED current |
| Количество посещений | distinct `client_key` среди посетителей в текущем фильтре дня и клуба | DAX `DISTINCTCOUNT(client_key)` | CONFIRMED — решение пользователя 2026-07-31 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `_accumrg7509` | движения неподтверждённых услуг | CONFIRMED source / states preserved | SV-099; full horizon state control before VD load: `Active=false = 0`, null key refs = 0; новый filter не вводится |
| `AccumRg7575`, `Document325` | посещения для когорты | CONFIRMED source / states pending | M, source catalog, BR-006 |
| `_document329`, `_document279` | ветки предварительной и групповой записи | CONFIRMED source / no multiplication | SV-099; independent branch-map control in `unconfirmed_service_debt_movement_source_control.sql` |
| `Reference132`, `Reference141X1`, `Reference163`, `Reference225` | клуб, клиент, услуга, сотрудник | CONFIRMED current sources | M, metadata, source catalog |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники | `AccumRg7575`, `Document325`, `Document329`, `Document279`, `Document313`, клиент, клуб, услуга и сотрудник каталогизированы; `AccumRg7509` добавлен настоящим mapping. | CONFIRMED catalog, metadata, M |
| Проверенные продукты | `mart.visit_client_day`, `mart.club_day_metrics`, факты ИП, ДПФУ и контроля предзаписи рассмотрены. | CONFIRMED catalog |
| Проверенные правила | BR-001, BR-002, BR-003, BR-006, BR-007, BR-013, BR-014 и BR-025 применимы. | CONFIRMED catalog |
| Сравнение гранулярности | `visit_client_day` — client-day; движение долга — event/ПЗ; `club_day_metrics` — только club-day. | CONFIRMED current M/DAX |
| Сравнение ключей | общий visit факт не хранит `prebooking_id`, движение долга не является событием посещения. | CONFIRMED |
| Сравнение семантики | ДПФУ/ИП — оказанные услуги, а данный факт — остаток неподтверждённой услуги as-of; контроль предзаписи не подтверждает денежный остаток. | CONFIRMED |
| Решение | `REUSE` `mart.visit_client_day` для обезличенной когорты; `NEW` `mart.unconfirmed_service_debt_movement`. | CONFIRMED — ADR-0021 / product admission |
| Причина решения | расширение client-day движениями и PII смешает event-grain с cohort-grain и нарушит BR-007; копия посещений не нужна. | CONFIRMED |
| Затронутые потребители | «Посещения Физкульт», «Посещения Пушкинский», «Контроль предварительной записи», ИП и ДПФУ не меняют grain или поля. | CONFIRMED |

## Риски и будущая валидация

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| CONFIRMED | Семантика графика «Количество посещений» | единица — уникальный клиент с посещением, а не число входов. | client-day grain и `DISTINCTCOUNT(client_key)`; решение пользователя 2026-07-31. |
| CONFIRMED | Доставка PII | код и ФИО клиента допускаются в report-specific detail для всех, у кого уже есть доступ к данному Power BI-отчёту. | решение пользователя 2026-07-31; физический механизм ограничения выбирается на реализации. |
| CONFIRMED | Частота обновления | ежедневная; Power BI доступен до 08:30 МСК, витрина завершается раньше. | BR-014 и решение пользователя 2026-07-31; end-to-end производительность — приёмка созданной витрины. |
| VALIDATED WITH OBSERVATION | ключ и state `AccumRg7509` | 482 347 movements имеют уникальный physical key; inactive/null ключи = 0. DAX sign и quantity `other` воспроизводятся по TXT; новый state-filter не вводится. | SV-099; as-of компонент дополнительно проверен DV-V05B. |
| VALIDATED WITH OBSERVATION | документные ветки | current branches не размножают движения; строки без ровно одной документной ветки намеренно не входят в current-M-compatible fact. Их число фиксируется independent source control на каждом snapshot (3 459 на horizon до 2026-08-28). | SV-099; current branch не меняется без отдельного решения. |
| VALIDATED SOURCE-SIDE | as-of остаток | На двух датах и двух фактических клубах BR-025 нет null/mismatch client-key и excess технического ключа; current DAX-алгебра дала сохранённые контрольные суммы. | DV-V05B; это не выдаётся за отсутствующую сверку с фактическим Power BI. |
| CONFIRMED | классификация посещения | BR-025 устанавливает общий физический ключ `Document325.Fld4164RRef = 9a5a4c90d2b1aede4b91dcd1abe84c43`. Он намеренно заменяет legacy `LIKE '%Посещение%'`; наблюдаемое расхождение 36 против 3 003 981 строк сохраняется как критичный артефакт. | user decision 2026-08-19; SV-099 DV-V06B; повторная замена правила без нового решения запрещена. |
| DEFERRED TO ACCEPTANCE | объём и SLA | Узкий current count измерен: `AccumRg7575` ≈ 33,6 млн строк / 29,1 ГБ, execution = 25,7 мс на горячем кэше и без disk/temp reads. End-to-end SLA проверяется при приёмке созданной витрины и её расписания. | DV-V07; global user decision 2026-08-19. |
