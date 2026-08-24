# Source-to-target mapping: «Подготовка к продлению»

Статус: `IMPLEMENTED AND VALIDATED — 2026-08-24`.
Reviewed DDL/source extract, independent reconciliation path и source evidence
зафиксированы до первого DDL: [Stage-3 validation](../source_metadata/preparation_renewal_stage3_validation_2026-08-24.md).

## Гранулярность

Кандидат одной строки:

> один контракт × контрольная точка подготовки `7/14/21/28/30`.

Кандидат ключа: `(contract_id, checkpoint_day)`.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица | Исходная колонка | Преобразование | PostgreSQL тип | NULL | Гранулярность | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|---|
| `contract_id` | стабильный идентификатор контракта | `Reference59` | `ID` | явное hex/text-представление ссылки | `text` | нет | contract × checkpoint | CONFIRMED current source | M `Абонементы` | уникальность `ID` |
| `contract_code` | отображаемый код для детализации | `Reference59` | `Code` | явный `text`; не ключ join | `text` | нет | contract × checkpoint | CONFIRMED current consumer and access policy BR-017 | M и скриншот модели | дубли `Code` |
| `client_id` | клиент контракта | `Reference59` | `Fld681` | явное hex/text-представление | `text` | нет | contract × checkpoint | CONFIRMED current source | M join с visit client | orphan, null |
| `membership_start_date` | дата начала контракта | `Reference59` | `Fld671` | `::date` | `date` | нет | contract × checkpoint | CONFIRMED current source | M | sentinel, end >= start |
| `membership_end_date` | дата окончания и база окна | `Reference59` | `Fld672` | `::date` | `date` | нет | contract × checkpoint | CONFIRMED current source | M/DAX | boundary, timezone |
| `access_club_id` | клуб доступа | `Reference59` | `Fld687` | явное hex/text-представление | `text` | нет | contract × checkpoint | CONFIRMED current source | M | orphan |
| `access_club_name` | название клуба для визуала | `Reference132` | `Description` | join по ID клуба | `text` | нет | contract × checkpoint | CONFIRMED current source | M | один клуб на ID |
| `checkpoint_day` | контрольный срез подготовки | generated | — | одно из `7,14,21,28,30` | `smallint` | нет | contract × checkpoint | CONFIRMED current model | M/DAX | допустимые значения |
| `checkpoint_date` | дата, на которой выводится срез | `Reference59` | `Fld672` | `membership_end_date - 121 days + checkpoint_day` | `date` | нет | contract × checkpoint | CONFIRMED user decision | пользователь 2026-07-29; текущий DAX | примеры на контрактах |
| `visit_count_to_checkpoint` | накопительное число посещений в 30-дневном окне к срезу | `AccumRg7575` | `Period`, `Fld7576`, `Fld7578`, `Fld7579` | события контракта и клиента; текущая M-логика 120–90 дней до окончания, кумулятивно по checkpoint | `integer` | нет, `0` | contract × checkpoint | CONFIRMED current calculation / technical semantics pending | M | rows vs documents vs quantity |
| `visit_bucket` | категория посещаемости | derived | — | `0`, `1`, `2`, `3`, `4+` | `text` | нет | contract × checkpoint | CONFIRMED | описание и DAX | границы |
| `target_visit_count` | минимум раз в неделю | generated | — | `1,2,3,4,4` для checkpoint `7,14,21,28,30` | `smallint` | нет | contract × checkpoint | CONFIRMED | описание | соответствие точке |
| `below_target_flag` | ниже целевой посещаемости | derived | — | `visit_count_to_checkpoint < target_visit_count` | `boolean` | нет | contract × checkpoint | CONFIRMED | описание | пороговые значения |
| `frozen_at_checkpoint_flag` | заморожен на дату среза | `InfoRg5859`, `AccumRg7478` | `Fld5860`, `Fld5862`, `Fld5863`, движения | legacy latest movement по `(contract_code, freeze_start_date)`; затем technical `contract_id` interval predicate | `boolean` | нет | contract × checkpoint | CONFIRMED — PR-V13 | DAX и Stage-3 source validation | legacy ↔ technical difference = 0 |
| `age_group` | возрастной срез | `Reference141X1`, `Reference59` | `Fld1507`, `Fld670` | точный календарный возраст на дату активации: `<14`, `14–17`, `18+` | `text` | да | contract × checkpoint | CONFIRMED user decision | пользователь 2026-07-29; BR-008 | дни рождения, null |
| `membership_tenure` | `New` / `Renew` / `Ex` | `Reference59` | `Fld694` | GUID `bc06…41f9` / `91e4…18f2` / `9e36…1498` | `text` | нет | contract × checkpoint | CONFIRMED — M and PR-V10 | current M | unexpected GUID = 0 after filter |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `Reference59` | контракт, клиент, даты, клуб, стаж | CONFIRMED current source | M, source catalogue |
| `Reference141X1` | дата рождения и код клиента | CONFIRMED physical source | M, source metadata, PR-V10 |
| `Reference132` | клуб | CONFIRMED current source | M, source catalogue |
| `AccumRg7575` | события посещений, связанные с контрактом и клиентом | CONFIRMED current source pair | M, PR-V12 |
| `Reference163` | отбор номенклатуры `посещение клуба` | CONFIRMED current source / textual filter pending | M, source catalogue |
| `AccumRg7478`, `InfoRg5859` | движения и интервалы заморозок | CONFIRMED current legacy rule | M, PR-V13—V15 |
| `InfoRg6015` | календарь Power BI | CONFIRMED current source | M; source metadata |
| Excel «Подготовка базы план» | план по дате и клубу | CONFIRMED external / excluded from SQL | пользовательское решение 2026-07-29; скриншот связей |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `docs/catalogs/source_objects.md` | `Reference59`, `Reference141X1`, `Reference132`, `AccumRg7575`, `Reference163`, `AccumRg7478`, `InfoRg5859` уже используются; `InfoRg6015` доказан source metadata, но пока отсутствует в каталоге. | CONFIRMED catalog, M and metadata |
| Проверенные продукты из `docs/catalogs/data_products.md` | Проверены `mart.contract_usage`, `mart.renewal_management_contract`, `mart.newcomer_engagement_milestone`; набора для этого 30-дневного окна нет. | CONFIRMED catalog |
| Проверенные правила из `docs/catalogs/business_rules.md` | BR-002, BR-003, BR-007, BR-008, BR-012, BR-013 применимы; для возраста принят BR-008. | CONFIRMED catalog and user decision |
| Сравнение гранулярности | `contract_usage`: контракт; `renewal_management`: заканчивающийся контракт; newcomer: контракт × клиент × checkpoint. Здесь контракт × checkpoint. | CONFIRMED evidence |
| Сравнение ключей | Кандидат `(contract_id, checkpoint_day)` не совпадает с ключами существующих продуктов. | CONFIRMED design evidence |
| Сравнение бизнес-семантики | Существующие факты считают весь срок, Renew или первые дни действия; отчёт считает месяц **до** периода продления и исключает заморозку в срезе. | CONFIRMED current logic |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | `NEW` `mart.preparation_renewal_checkpoint`; REUSE общих календаря/клубов и source rules. | DESIGNED — ADR-0013 |
| Причина решения | Общий grain без подтверждённых потребителей не выделяется; existing facts имеют несовместимое время. | CONFIRMED BR-002 |
| Затронутые существующие потребители | `newcomer_engagement` и `renew_contract_usage` делят technical validation посещений; их утверждённая бизнес-логика не меняется. | CONFIRMED |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| CONFIRMED safeguard | `AccumRg7575.Fld7578 → Reference59.ID` | 496 089 qualified visit rows сохраняют current pair contract+client; технический key не размножен | PR-V12 |
| CONFIRMED preserve-current | states | `Active`, deletion, posting and storno не добавлены как filters; marked/inactive source profile записан | PR-V11—V12 |
| CONFIRMED safeguard | заморозка | direct interval existence отклонён: 2 347 differences; legacy latest-movement rule сохраняется | PR-V13—V14 |
| CONFIRMED | code/name joins | contract/code/name не используются как target join keys; technical contract and club IDs заполнены без orphan | PR-V11 |
| NOT_APPLICABLE | внешний план | внешний Excel намеренно не переносится на SQL-сервер | остаётся отдельной таблицей Power BI |

## Результат read-only проверок

`SV-077` (live read-only, 2026-08-11) подтвердил существование восьми
physical relations. Bounded cohort из 100 контрактов с окончанием 2026-07-31
дала 500 уникальных checkpoint-строк без duplicate key; все даты равны
2026-04-08/15/22/29 и 2026-05-01, 1 360 visit-строк и 54 frozen point.
Одновременно `AccumRg7575` содержит 240 304 contract orphan и 146 139
client-owner mismatch, а `InfoRg5859` — 71 обратный интервал и 22 998
duplicate groups. Эти наблюдения не разрешают менять current joins, границы
или state-фильтры без отдельного решения по BR-018.

Stage-3 PR-V10—V16 и initial/rerun PR-R01—PR-R06 закрыли эти проверки без
изменения current business logic. Exact totals и measured transport/rollback
зафиксированы в [execution evidence](../reports/preparation_renewal_checkpoint_execution_2026-08-24.md).
