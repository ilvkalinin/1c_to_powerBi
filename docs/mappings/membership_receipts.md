# Source-to-target mapping: поступления по членству

Статус:
`BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0017 / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-083, SV-105, SV-107, SV-112; Stage 3 deferred`.

Этот mapping фиксирует текущую логику отчёта и не утверждает физический объект
или SQL. На `STAGE_1_LOCAL_ANALYSIS` DDL/DML и серверные проверки запрещены.

## Гранулярность

Подтверждены два разных уровня:

1. движение поступления — квалифицированная строка источника
   `source_kind × recorder_id × line_no`; текущий Power Query теряет `line_no`
   и агрегирует широкий набор полей;
2. единица контрактных KPI:
   - предоплата — один квалифицированный `contract_id`;
   - рекарринг — один квалифицированный ежемесячный платёж контракта;
   - membership-услуги не входят в этот набор.

Бизнес-grain второго уровня `CONFIRMED`. Для рекарринга это
`contract_id × payment_period`: `payment_period` — текущий PBI-столбец
`Текст после разделителя`, полученный из `АналитикаУчета`. Все движения одной
группы суммируются; уникальность отдельных строк внутри неё не требуется.
SV-094 корректно зафиксировал множественность движений, но ошибочно назвал её
ошибкой ключа; исправление интерпретации — SV-096.

Кандидат технического ключа движения:
`(source_kind, recorder_id, line_no)` — `VALIDATION_PENDING`.

## Целевые колонки движения и контрактных атрибутов

| Целевая колонка | Бизнес-описание | Исходная таблица | Исходная колонка | Преобразование | PostgreSQL тип | NULL | Гранулярность | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|---|
| `source_kind` | ветка денежного источника | вычисление | — | `contract_advance`, `membership_service` | `text` | нет | движение | CONFIRMED target scope | M + user decision 2026-07-31 | MR-V11 branch reconciliation |
| `recorder_id` | документ-регистратор | `AccumRg7370/7739` | `RecorderRRef` | канонический ID | `text` candidate | нет | движение | CONFIRMED source / type pending | M | MR-V02 |
| `recorder_line_no` | номер строки движения | те же регистры | `LineNo` | без изменения | `integer` candidate | нет | движение | VALIDATION_PENDING | source metadata required | MR-V02 |
| `receipt_date` | дата поступления | `AccumRg7370/7739` | `Period` | `::date` | `date` | нет | движение | CONFIRMED current DAX | M/DAX | MR-V12 |
| `metric_date` | дата количества/цен/длительности | movement + `Reference59` | `Period`, `Fld670` | recurring → movement date; prepayment → activation date; service → NULL | `date` | да у услуг | контрактная единица | CONFIRMED target rule | DAX + user decision 2026-07-31 | MR-V12 |
| `contract_id` | устойчивый ID контракта | registers → `Reference59` | `Fld7371/Fld7741/Fld7655` → `ID` | канонический ID | `text` candidate | да у услуг | движение / контракт | CONFIRMED current source | SQL/M | orphan test |
| `client_key` | обезличенный ключ клиента для predecessor и менеджерских срезов | `Reference59`, `AccumRg7739` | `Fld681`, `Fld7740` | стабильный protected key; без ФИО | `text` | да у услуг | движение | VALIDATED RISK — SV-116: одинаковые даты активации не имеют второго порядка | DAX predecessor | MR-V08 |
| `payment_period` | платёжный период рекарринга | `Reference134` через `AccumRg7370.Fld7376` | `Description` | текущий M: `Text.AfterDelimiter(АналитикаУчета, "; ", {0, RelativePosition.FromEnd})`, затем numeric | `integer` | да | контрактная единица | CONFIRMED current M/DAX | PBIT `Текст после разделителя` | SV-096 |
| `kpi_unit_kind` | тип единицы количества | вычисление | `payment_type` | предоплата → `contract`; рекарринг → `recurring_payment`; услуга → NULL | `text` | да | контрактная единица | CONFIRMED user decision 2026-07-31 | user decision | scenario matrix |
| `kpi_unit_key` | логический ключ единицы количества | вычисление | `contract_id`, `payment_period` | предоплата → contract ID; рекарринг → `contract_id × payment_period`; сумма движений — `SUM(amount_signed)` по этой группе | `text` candidate | да | контрактная единица | CONFIRMED current M/DAX | PBIT + BR-016 | SV-096/MR-V11 |
| `movement_kind` | приход/расход регистра | registers | `RecordKind` | текущий код; значение проверяется | `smallint` candidate | нет | движение | CONFIRMED source / semantics pending | M | MR-V03 |
| `recorder_type` | передача/перевод/возврат/карта/чек/безнал/ПКО/РКО и т. п. | 14 document joins | наличие документа | текущий приоритет M | `text` | да | движение | CONFIRMED current M / exclusivity pending | M | MR-V04 |
| `amount_raw` | исходная сумма | `AccumRg7370/7739` | `Fld7377/Fld7749` | без знакового CASE | `numeric` | нет | движение | CONFIRMED source | M | MR-V03 |
| `amount_signed` | сумма после правила документа | `AccumRg7370` | `RecordKind`, recorder type, `Fld7377` | текущий sign CASE; ПКО → 0 | `numeric` | нет | движение | CONFIRMED current M / partial physical state-sign validation; ПКО `RecordKind=1` не встречен | M, SV-112 | MR-V03/MR-V04 |
| `co_access_amount` | сумма со-доступа, вычитаемая из аванса | `AccumRg7739` | `Fld7749` | текстовая классификация со-доступа, aggregate contract+date | `numeric` | да (`0`) | contract × date | VALIDATED current PBIT cardinality — SV-114 | M/DAX | MR-V07 |
| `receipt_amount_net` | контрактное поступление без со-доступа | вычисление | `amount_signed`, `co_access_amount` | `amount_signed - co_access_amount` | `numeric` | нет | движение | CONFIRMED current DAX | `_Сумма итог2` | branch reconciliation |
| `service_group` | membership-категория услуги | `Reference163` | `Description` | только со-доступ, полотенца, гостевой визит, заморозка, переоформление, адаптация ДРЦ, вход для детей | `text` | да | движение услуги | CONFIRMED target scope | M + user decision 2026-07-31 | MR-V10/MR-V11 |
| `movement_club_id` | клуб движения услуги | `AccumRg7739` | `Fld7746` | канонический club ID | `text` | да | движение | CONFIRMED current source | SQL | orphan |
| `access_club_id` | основной клуб доступа контракта | `Reference59` | `Fld687` | канонический club ID | `text` | да | контракт | CONFIRMED current source | SQL | orphan |
| `sales_point_club_id` | точка продажи | `Reference59` | `Fld701` | role-playing club dimension | `text` | да | контракт | CONFIRMED current source | SQL/model | orphan |
| `reporting_club_id` | клуб основного факта | вычисление | три роли клуба | contract → access club; service → movement club; co-access → access club | `text` | нет | движение | CONFIRMED current M/DAX | M/DAX | page totals by role |
| `manager_id` | менеджер контракта/чека | `Reference59`, `Document346` | `Fld683`, `Fld4909` | stable employee ID | `text` | да | движение | CONFIRMED current source | M | orphan |
| `contract_activation_date` | дата активации | `Reference59` | `Fld670` | `::date` | `date` | да | контракт | CONFIRMED current source | SQL/M | boundary |
| `contract_start_date` | начало членства | `Reference59` | `Fld671` | `::date` | `date` | да | контракт | CONFIRMED current source | SQL/M | end >= start |
| `contract_end_date` | окончание членства | `Reference59` | `Fld672` | `::date` | `date` | да | контракт | CONFIRMED current source | SQL/M | end >= start |
| `contract_term_days` | срок из карточки контракта | `Reference59` | `Fld693` | явный numeric | `numeric` candidate | да | контракт | CONFIRMED current source / physical type pending | SQL/M | compare DATEDIFF |
| `free_freeze_before_activation_days` | бесплатная заморозка до активации | `AccumRg7478`, paid freeze branches, `AccumRg7646` | `Fld7481`, `Fld7655`, `Fld7659`, `Reference163.Fld1756` | total freeze minus paid freeze, including sold freeze aggregated per contract; floor at 0 | `numeric` | нет (`0`) | контракт | VALIDATED CURRENT-PBIT DEDUP — SV-117: ОРП joins кратны до существенного `Table.Distinct`, порядок сохранён | DOCX + user M 2026-07-31 | MR-V09 |
| `effective_duration_days` | длительность для KPI | вычисление | payment type, term, freeze | service blank; recurring 30.42; prepayment term + free freeze | `numeric` | да | контрактная единица | CONFIRMED current DAX | `_ДлитКонтрСуперНовая` | MR-V11 |
| `source_stage` | исходный NEW/RENEW/EX | `Reference59` | `Fld694` | current `Enum402` mapping; нулевая ссылка остаётся пустой | `text` | да | контракт | VALIDATED CURRENT-PBIT COVERAGE — SV-118: 458 нулевых ссылок без fallback | `стаж_контракта` | MR-V10 |
| `super_stage` | динамический ресурс KPI | predecessor contract + analytics | несколько | `NEW`, `RENEW`, `RENEW(БП)`, `EX`, `Продажа`, `Списание`, `Клип-карты` | `text` | нет | контрактная единица | CONFIRMED target rule | PBIT DAX + user decision 2026-07-31 | scenario matrix |
| `payment_type` | тип оплаты | `Reference59` + current M | `Fld699`, contract type | `9bd3ea4748457ee94b2011de6d9687d7` → `Рекарринг`; другой non-NULL → `Предоплата`; `NULL` → `Услуга`; `Кредит`/`Бесплатный` отображаются в `Предоплате`, когда не исключены scope | `text` | нет | движение | VALIDATED CURRENT-PBIT COVERAGE — SV-118 | current M + BR-024 | MR-V10 |
| `payment_source` | канал продажи | recorder documents + product name | несколько | current COALESCE/override; сохранять `Клуб`, `Website`, `App`, `App сотрудника`, `Web customer`, `Рассрочка` | `text` | да | движение | VALIDATED CURRENT-PBIT COVERAGE — SV-119; Website/App сотрудника не наблюдались | M/DAX + user decision 2026-07-31 | MR-V10 |
| `product_id` | номенклатура контракта/услуги | `Reference59`, `AccumRg7739`, `Reference163` | `Fld685/Fld7743`, `ID` | stable product ID | `text` | да | движение | CONFIRMED current source | SQL/M | orphan |
| `product_age_category` | продуктовая возрастная категория | `Reference163` | `Fld1741` + name/type | `Взрослые`/`Дети`/`Юниоры`; current `Детские секции` → `Дети` | `text` | да | контракт | VALIDATED CURRENT-PBIT COVERAGE — SV-118 | PBIT M/DAX + user correction 2026-07-31 | MR-V10 |
| `purchase_type` | передача/продажа | `Reference59` | `Fld668` | current GUID mapping | `text` | да | контракт | CONFIRMED current DAX | DAX | GUID coverage |
| `membership_kind` | стандартный/подарок/совместный/эксклюзивный | `Reference59` | `Fld667` + product name | current GUID/text mapping | `text` | да | контракт | CONFIRMED current DAX | DAX | coverage |
| `club_access_type` | сетевой/локальный | `Reference59`, `InfoRg8595` | `Fld697`, `Fld8603/8597...` | product override then contract GUID | `text` | да | контракт | VALIDATED CURRENT-PBIT COVERAGE — SV-119/120 | DAX | MR-V10 |
| `access_time_type` | дневной/безлимитный/ограничение | `InfoRg8595`, product name | `Fld8599`, description | current text override then index | `text` | да | контракт | VALIDATED CURRENT-PBIT LOOKUP AND FALLBACK — SV-120 | DAX | MR-V10 |
| `access_zone` | VIP/Exclusive/кандидат/весь клуб | product name + club | `Description` | current ordered text search | `text` | нет | контракт | VALIDATED CURRENT-PBIT COVERAGE — SV-119 | DAX | MR-V10 |
| `list_contract_price` | полная цена для режима П | `AccumRg7646/7739` → `_Спр Абонементы.price` | `Fld7659/Fld7749` | текущая contract aggregation; tie-break pending | `numeric` | да | контрактная единица | VALIDATED RISK — SV-115: multiple price pairs, current `Table.Distinct` preserved | SQL/M/DAX | MR-V06 |
| `calculation_mode` | правило цены по клубу | club mapping | club name | Пушкинский=`П`, УК/ДРЦ=`УК`, прочие=`Ф` | `text` | нет | контракт | CONFIRMED current DAX / hard-code risk | DAX | all clubs covered |

## Производные меры Power BI

| Русское имя меры | Формула над целевым набором | Статус |
|---|---|---|
| `Поступления всего` | все квалифицированные движения контрактов + только семь утверждённых membership-услуг; прочие направления исключаются | CONFIRMED user decision 2026-07-31 |
| `Количество` | один `contract_id` предоплаты или одна группа `contract_id × payment_period` рекарринга; услуги исключаются | CONFIRMED current M/DAX + BR-016 |
| `Средняя цена контракта` | сумма расчётной цены квалифицированных KPI-единиц / `Количество` | CONFIRMED target rule |
| `Продолжительность` | average `effective_duration_days` по тому же квалифицированному KPI-набору / 30.42 | CONFIRMED target rule |
| `Средняя цена месяца` | `Средняя цена контракта / Продолжительность` | CONFIRMED current formula |

Все меры неаддитивны, кроме поступлений. `Поступления всего` намеренно имеет
более широкий денежный scope, чем четыре контрактных KPI; общий знаменатель
или единый агрегированный факт для всех пяти показателей запрещён.

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `AccumRg7370` | движения авансов/оплат по контрактам | CONFIRMED current source / key, states and sign pending | supplied M |
| `AccumRg7739` | membership-услуги, со-доступ и цена | CONFIRMED current source / service scope and states pending | supplied M |
| `AccumRg7478` | движения заморозки | CONFIRMED current source / interval and states pending | supplied M |
| `AccumRg7646` | цена продажи и продажа заморозки | CONFIRMED current source / cardinality pending | supplied M |
| `Reference59` | контракт, клиент, даты, клубы, стаж и типы | CONFIRMED current source | supplied SQL/M |
| `Reference134` | источник `АналитикаУчета`, из которого текущий M извлекает платёжный период | CONFIRMED current M/DAX | supplied PBIT |
| `Reference141X1`, `Reference163`, `Reference132`, `Reference225` | клиент, продукт, клуб, сотрудник | CONFIRMED current source / states pending | supplied SQL/M |
| `InfoRg5596` | базовая цена клуба | CONFIRMED current source / as-of tie pending | supplied M |
| `InfoRg8595` и `Reference109` | индекс параметров номенклатуры | CONFIRMED current source / uniqueness pending | supplied M |
| recorder documents `285/296/304/305/315/316/317/327/331/332/333/339/340/346` | тип движения, дата и канал | CONFIRMED current source / polymorphic exclusivity pending | supplied SQL/M |
| `Document266`, `Document315.VT3894`, `Document346.VT4924` | бесплатная/платная заморозка до активации | CONFIRMED current source / joins pending | supplied M |
| `AccumRg7646`, `Document332`, `Reference163/59` | продажа дней заморозки с абонементом | CONFIRMED current source / states and joins pending | user M 2026-07-31 |
| планы Power BI | неизменяемые Excel-файлы текущего и среднесрочного планов | CONFIRMED external / не входят в PostgreSQL target | user decision 2026-07-31 |
| PBIT `DataModelSchema` | 108 таблиц, 121 связь, DAX/M и роли дат | CONFIRMED local model evidence | supplied PBIT 2026-07-31 |

## Требования к связям целевой модели Power BI

PBIT подтверждает общую звезду и одновременно показывает, почему денежный
факт и контрактный KPI-набор должны оставаться разными сущностями.

| Измерение / роль | Движения поступлений | Контрактные KPI | Требование |
|---|---|---|---|
| календарь движения | `receipt_date` | не используется для предоплаты; используется рекаррингом | активная роль для суммы поступлений |
| календарь KPI | не используется услугами | `metric_date` | отдельная роль; активация для предоплаты, движение для рекарринга |
| календарь окончания | — | `contract_end_date` | неактивная role-playing связь для заканчивающихся контрактов |
| основной клуб | `reporting_club_id` | `access_club_id` | общая dimension клуба, `1:*`, single direction |
| клуб продажи | `sales_point_club_id` | `sales_point_club_id` | role-playing club; должен фильтровать оба набора |
| менеджер | `manager_id` | `manager_id` | общая employee dimension; должен фильтровать четыре контрактных KPI |
| суперстаж | `super_stage` | `super_stage` | общий трёхсторонний фильтр движений, KPI и Excel-планов |
| возраст продукта | NULL у membership-услуг | `product_age_category` | общий трёхзначный справочник `Взрослые/Дети/Юниоры` |
| тип оплаты | `payment_type` | `payment_type` | общий справочник после объединения Credit/Free с Prepayment |
| канал | `payment_source` | `payment_source` | шесть значений без потери редко встречающихся категорий |

В текущем PBIT `Сотрудники` и role клуба продажи связаны с `Авансы по
контрактам`, но не с рассчитанной `Таблица Активных Контрактов`. Поэтому
`Кол Факт`, средняя цена и продолжительность, читающие KPI-таблицу, могут не
реагировать на менеджера и клуб продажи. В целевой модели это расхождение
запрещено.

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `source_objects` | `AccumRg7370/7478/7646/7739`, contracts, clubs, clients, products and checks are catalogued or added by this mapping | CONFIRMED catalog; technical validation deferred |
| Проверенные продукты из `data_products` | `mart.revenue_group_summary_daily`, `mart.contract_usage`, `mart.renewal_management_contract`, newcomer facts, children sales, ancillary revenue | CONFIRMED catalog |
| Проверенные правила из `business_rules` | BR-001/002/003/007/010/012/013/014/015/016 | CONFIRMED; BR-008 не применяется к продуктовой категории возраста этого отчёта |
| Сравнение гранулярности | group summary is date×club×article; contract usage is contract; ancillary uses other revenue movements; this report needs payment movement plus contract KPI unit | CONFIRMED mismatch |
| Сравнение ключей | group summary loses contract/recorder; contract_usage lacks payment movement; current report drops LineNo | recurring KPI-grain `contract × payment_period` CONFIRMED; movement states and full-domain controls remain pending |
| Сравнение бизнес-семантики | membership branch of group summary shares 7370/7739 sign/source rules, but cannot serve product/manager/stage/price/duration slices | CONFIRMED |
| Решение (`REUSE` / `EXTEND` / `NEW`) | `EXTEND` source-rule membership branches of revenue summary; `REUSE` dimensions; `NEW` `mart.membership_receipt_movement` и `mart.membership_contract_kpi_unit` | DESIGNED — ADR-0017 |
| Причина решения | daily group aggregate is too coarse; contract usage measures visits, not money; copying raw registers into separate report tables would duplicate logic | CONFIRMED comparison |
| Затронутые существующие потребители | `Свод выручка ГК`, `Титульный лист`, `Отчет членство для правления` | CONFIRMED; board report REUSE by [mapping](membership_board.md) |

## Риски, блокеры и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| CONFIRMED | рекарринговая KPI-единица | текущий PBI суммирует все движения `contract_id × payment_period`; множественность строк в группе ожидаема | SV-096 / BR-016 |
| PARTIALLY VALIDATED | source keys/states/signs | SV-112/113 подтвердили current state/sign и отсутствие размножения 14 document joins; другие joins и непредставленная ветка ПКО остаются открыты | MR-V01–MR-V05 |
| VALIDATED RISK | predecessor contract | SV-116: 508 пар `клиент × дата активации` имеют несколько договоров; PBIT сортирует только по дате и не имеет business tie-break | сохранять current order по BR-018; решение о tie-break — отдельная доработка |
| VALIDATED | `InfoRg8595` | SV-120: 144 current-PBIT номенклатуры имеют 144 строки; среди 93 используемых конфликтов времени нет | current `Table.Distinct(product_id)` сохраняется без нового порядка |
| CONFIRMED MODEL RISK | manager and sales-club propagation | current calculated KPI table lacks the corresponding shared-dimension relationships | require both keys/relationships in future KPI fact |
| CONFIRMED MODEL RISK | field visibility | 205 columns across five main facts/plans are all visible in PBIT | expose only Russian business fields; hide technical keys and nonadditive helpers |
| CONFIRMED MODEL RISK | automatic date tables | PBIT contains 55 `LocalDateTable_*` objects | use one explicit calendar with documented role-playing dates |
| REJECTED | reuse `mart.revenue_group_summary_daily` as report fact | loses contract, manager, product and duration | retain only source-rule reconciliation |
| REJECTED | reuse `mart.contract_usage` | different fact: visits over one contract, no receipt movements | source rule/dimensions only |
| REJECTED | plans in PostgreSQL mart | user confirmed stable Excel files remain in Power BI | keep separate external plan facts |
| REJECTED | direct plan-to-movement join | incompatible grain and sum multiplication | separate plan facts with shared dimensions |
| REJECTED | PII in target by default | no confirmed consumer on shown pages | protected key only |

## Stage 2 evidence — SV-083

`AccumRg7370`, `AccumRg7739`, `Reference59` и `Reference134` существуют. В
bounded 2026 выборках по 100 строк оба регистра имеют 100 technical keys и 0
orphan-contract. Наблюдаемые `RecordKind` не интерпретируются без current M
sign CASE; recorder exclusivity, states, freeze and price joins
остаются `VALIDATION_PENDING` перед реализацией.
