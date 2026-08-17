# Source-to-target mapping: «Отчет по посещаемости клиентов с долгами»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0021 / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED — SV-089, SV-099 / IMPLEMENTATION DEFERRED`.

Спроектирован `mart.unconfirmed_service_debt_movement`; DDL и реализация
отложены. Mapping описывает
два несовместимых по grain логических набора, которые не должны смешиваться.

## Stage 2 evidence — SV-089, SV-099

SV-002/SV-006 подтверждают физические relations current M; SV-008 —
физический `RecordKind` `_accumrg7509`; SV-013/SV-017 — PK-side cardinality
`_accumrg7575 → _document325` и reference dimensions основной visit-ветки.
Следовательно, `mart.visit_client_day` остаётся допустимым reuse только для
cohort, а `AccumRg7509` — отдельным movement fact. SV-099 подтвердил
уникальность ключа, отсутствие пустых ключевых ссылок и отсутствие branch
multiplication. `prebooking_id` не уникален по клиенту, поэтому as-of key
остаётся `client × prebooking`. Стабильная visit classification, правило для
quantity `other`, as-of controls и SLA остаются открытыми.

[`SV-099 SQL`](../source_metadata/validation_sql/visits_debt_global_review_2026-08-17.sql)
выполнен read-only. Его полный результат и критичный артефакт `mvarchar` — в
[`server validation`](../source_metadata/server_validation_2026-08-14.md#sv-099--посещаемость-клиентов-с-долгами-movement-and-branch-controls).
Реализация не разрешена.

## 1. Логический набор движений долга по услуге

Гранулярность одной строки:

> одно движение регистра неподтверждённой услуги: `период × регистратор × номер строки`.

Логический ключ: кандидат `(debt_event_at, recorder_id, recorder_line_no)`;
не подтверждён до DV-V01. Бизнесовый as-of ключ: `client_key × prebooking_id`.

| Целевая колонка | Бизнес-описание | Источник / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `debt_event_at` | момент движения долга | `AccumRg7509.Period` | без округления до момента as-of; день визуала = `::date` | `timestamp` UNKNOWN | нет | CONFIRMED source | DV-V01 |
| `recorder_id`, `recorder_line_no` | технический ключ движения | `AccumRg7509.Recorder`, `LineNo` | сохранить до source-side дедупликации | `UNKNOWN`, `integer` UNKNOWN | нет | CONFIRMED metadata | DV-V01 |
| `record_kind` | вид движения | `AccumRg7509.RecordKind` | сохранить исходный код; DAX-классы определяются количеством | `smallint` UNKNOWN | нет | CONFIRMED source | DV-V01, DV-V02 |
| `client_key` | стабильный ключ cohort/as-of | `AccumRg7509.Fld7511` | защищённый стабильный ключ | `UNKNOWN` | нет | CONFIRMED need | DV-V04 |
| `client_code`, `client_name` | отображаемый код и ФИО | `Reference141X1.Code`, `Description` | report-specific PII detail; доступен всем, у кого есть доступ к данному Power BI-отчёту | `text` | да | CONFIRMED — решение пользователя 2026-07-31 | DV-V04 |
| `club_id` | клуб услуги/долга | `AccumRg7509.Fld7510` | стабильный идентификатор, не имя | `UNKNOWN` | нет | CONFIRMED source | DV-V03 |
| `prebooking_id` | предварительная/групповая запись, по которой возникает долг | `AccumRg7509.Fld7512` | сохранить до source-side aggregation | `UNKNOWN` | нет | CONFIRMED metadata | DV-V04 |
| `service_id`, `service_name` | услуга долга и название в detail | `AccumRg7509.Fld7513`, `Reference163.Description` | ID — всегда; имя — только detail | `UNKNOWN`, `text` | да | CONFIRMED current consumer | DV-V03, DV-V06 |
| `employee_id`, `employee_name` | оказавший услугу сотрудник | `Document329.Fld4322` / `Document279.Fld3223` → `Reference225` | выбрать ветку по типу регистратора | `UNKNOWN`, `text` | да | CONFIRMED current source / branch pending | DV-V03 |
| `service_start_at`, `service_end_at` | время услуги | `AccumRg7509.Fld7514`, `Fld7515` | без замены на период движения | `timestamp` UNKNOWN | да | CONFIRMED source | DV-V03 |
| `quantity_delta` | вклад в статус неподтверждённой услуги | `AccumRg7509.Fld7516`, `RecordKind` | классы базовой/подтверждения/двух отмен — по DAX | `numeric` UNKNOWN | нет | CONFIRMED current calculation | DV-V05 |
| `amount_delta` | знаковая сумма движения | `AccumRg7509.Fld7517`, `RecordKind` | current M: `RecordKind = 1` умножить на `-1`, иначе оставить знак | `numeric` UNKNOWN | нет | CONFIRMED current calculation | DV-V05 |

## 2. Когорта посетителей

Используется существующий кандидат общего факта `mart.visit_client_day`, только
если его `client_key` можно безопасно связать с controlled client detail. Факт
не расширяется PII-полями.

Гранулярность: дата фактического посещения × фактический клуб × стабильный клиент.

| Целевая колонка | Бизнес-описание | Источник / преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|
| `visit_date` | день включения клиента в когорту | `AccumRg7575.Period` / `Document325`; precedence и состояния подтвердить | `date` | нет | CONFIRMED current / technical pending | DV-V02, DV-V06 |
| `visit_club_id` | фактический клуб посещения | `AccumRg7575.Fld7577` и/или `Document325.Fld4167` | `UNKNOWN` | нет | CONFIRMED rule — BR-006 | DV-V06 |
| `client_key` | клиент для пересечения с движениями долга | общий защищённый ключ | `UNKNOWN` | нет | CONFIRMED need | DV-V04 |
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
| `AccumRg7509` | движения неподтверждённых услуг | CONFIRMED source / states pending | M и source metadata |
| `AccumRg7575`, `Document325` | посещения для когорты | CONFIRMED source / states pending | M, source catalog, BR-006 |
| `Document329`, `Document279`, `Document313` | ветки предварительной, групповой записи и отмены | CONFIRMED current source / cardinality pending | M и source catalog |
| `Reference132`, `Reference141X1`, `Reference163`, `Reference225` | клуб, клиент, услуга, сотрудник | CONFIRMED current sources | M, metadata, source catalog |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники | `AccumRg7575`, `Document325`, `Document329`, `Document279`, `Document313`, клиент, клуб, услуга и сотрудник каталогизированы; `AccumRg7509` добавлен настоящим mapping. | CONFIRMED catalog, metadata, M |
| Проверенные продукты | `mart.visit_client_day`, `mart.club_day_metrics`, факты ИП, ДПФУ и контроля предзаписи рассмотрены. | CONFIRMED catalog |
| Проверенные правила | BR-001, BR-002, BR-003, BR-006, BR-007, BR-013 и BR-014 применимы. | CONFIRMED catalog |
| Сравнение гранулярности | `visit_client_day` — client-day; движение долга — event/ПЗ; `club_day_metrics` — только club-day. | CONFIRMED current M/DAX |
| Сравнение ключей | общий visit факт не хранит `prebooking_id`, движение долга не является событием посещения. | CONFIRMED |
| Сравнение семантики | ДПФУ/ИП — оказанные услуги, а данный факт — остаток неподтверждённой услуги as-of; контроль предзаписи не подтверждает денежный остаток. | CONFIRMED |
| Решение | `REUSE` `mart.visit_client_day` для обезличенной когорты; `NEW` `mart.unconfirmed_service_debt_movement`. | DESIGNED — ADR-0021 |
| Причина решения | расширение client-day движениями и PII смешает event-grain с cohort-grain и нарушит BR-007; копия посещений не нужна. | CONFIRMED |
| Затронутые потребители | «Посещения Физкульт», «Посещения Пушкинский», «Контроль предварительной записи», ИП и ДПФУ не меняют grain или поля. | CONFIRMED |

## Риски и будущая валидация

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| CONFIRMED | Семантика графика «Количество посещений» | единица — уникальный клиент с посещением, а не число входов. | client-day grain и `DISTINCTCOUNT(client_key)`; решение пользователя 2026-07-31. |
| CONFIRMED | Доставка PII | код и ФИО клиента допускаются в report-specific detail для всех, у кого уже есть доступ к данному Power BI-отчёту. | решение пользователя 2026-07-31; физический механизм ограничения выбирается на реализации. |
| CONFIRMED | Частота обновления | ежедневная; Power BI доступен до 08:30 МСК, витрина завершается раньше. | BR-014 и решение пользователя 2026-07-31; производительность проверить DV-V07. |
| VALIDATION_PENDING | ключ и state `AccumRg7509` | `RecordKind` физически подтверждён, но `Active`, uniqueness и знаки не проверены. | DV-V01–DV-V02; новый control не выполнен без local PostgreSQL client/driver. |
| VALIDATION_PENDING | документные ветки | join к `Document329/279/313` может терять или размножать строки. | DV-V03; новый control не выполнен без local PostgreSQL client/driver. |
| VALIDATION_PENDING | as-of остаток | не доказано контрольными датами, что формула закрывает каждую ПЗ. | DV-V04–DV-V05; independent control отсутствует. |
| VALIDATION_PENDING | классификация и состояние посещения | `LIKE` и отсутствие status-фильтров не дают стабильную cohort. | DV-V02, DV-V06; новый control не выполнен без local PostgreSQL client/driver. |
| VALIDATION_PENDING | объём и SLA | без объёма нельзя выбрать физический объект или refresh. | DV-V07; independent performance evidence отсутствует. |
