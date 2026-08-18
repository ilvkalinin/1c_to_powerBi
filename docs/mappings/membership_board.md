# Source-to-target mapping: «Отчёт членство для правления»

Статус:
`BUSINESS MAPPING COMPLETE / REUSE CONFIRMED / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-083 / IMPLEMENTATION DEFERRED`.

## Гранулярность и ключи

Отдельного board-факта нет.

- денежное движение: полностью повторяет grain
  `membership_receipts` — `source_kind × recorder_id × line_no`;
- контрактная KPI-единица: контракт предоплаты или квалифицированный
  ежемесячный платёж рекарринга;
- планы: отдельные факты Power BI на собственном grain;
- визуальные агрегаты: производные и не меняют логический ключ.

SV-083 подтвердил bounded физические technical keys движения и отсутствие
orphan-contract в двух исходных регистрах. SV-094 подтвердил полный movement
key по уникальному индексу; SV-096 уточнил, что множественность строк
`contract × payment_period` — ожидаемая сумма движений одного платежа, а не
ошибка ключа.

SV-105 наблюдал полный 2026 разрез состояний общих движений: 46 416
неактивных строк есть у контрактных авансов, у membership-услуг их нет. Это
не меняет current M sign/state logic и не разрешает вводить новый filter.

## Повторно используемые целевые поля

Полное происхождение полей зафиксировано в
`docs/mappings/membership_receipts.md`. Ниже перечислен контракт потребителя;
новых source-колонок board-отчёт не добавляет.

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Grain | Статус | Доказательство | Тест |
|---|---|---|---|---|---|---|---|---|---|
| `source_kind` | ветка поступления | mapping `membership_receipts` | без изменения | `text` | нет | движение | CONFIRMED REUSE | MR mapping + PBIT | MR-V11 |
| `source_movement_key` | технический ключ движения | `AccumRg7370/7739` | bounded physical composite key; полный domain pending | `text` candidate | нет | движение | PARTIALLY VALIDATED — SV-083 | MR mapping | MR-V02/MR-V03 |
| `receipt_date` | дата денежного движения | `Period` | `::date` | `date` | нет | движение | CONFIRMED REUSE | BR-015 | MB-V07 |
| `metric_date` | дата контрактного KPI | movement / activation | recurring → movement; prepayment → activation | `date` | да у услуг | KPI unit | CONFIRMED REUSE | BR-015 | MB-V07 |
| `kpi_unit_key` | единица количества | contract / `payment_period` | предоплата → contract; рекарринг → `contract × payment_period` | `text` candidate | да у услуг | KPI unit | CONFIRMED REUSE | BR-016 + MR mapping | SV-096/MB-V01 |
| `receipt_amount_net` | чистое поступление | registers + co-access | эталонная MR-логика | `numeric` | нет | движение | CONFIRMED REUSE | MR mapping | MB-V01 |
| `calculation_price` | сумма для средней цены | movement / contract price | эталонное правило по типу расчёта | `numeric` | да | KPI unit | CONFIRMED REUSE | MR mapping | MB-V01 |
| `effective_duration_days` | длительность KPI | contract term + freeze | BR-016 | `numeric` | да | KPI unit | CONFIRMED REUSE | MR mapping | MB-V01 |
| `reporting_club_id` | основной клуб факта | movement/access club | эталонная роль клуба | `text` | нет | движение | CONFIRMED REUSE | MR mapping | MB-V06 |
| `sales_point_club_id` | клуб продажи | `Reference59.Fld701` | role-playing key | `text` | да | contract | CONFIRMED REUSE | MR mapping | MB-V06 |
| `manager_id` | менеджер | contract/check | stable employee key | `text` | да | movement/KPI | CONFIRMED REUSE | MR mapping | MB-V06 |
| `super_stage` | ресурс | contract history + analytics | семь утверждённых значений | `text` | нет | movement/KPI | CONFIRMED REUSE | MR mapping + board PBIT | MB-V06 |
| `product_age_category` | возраст продукта | `Reference163` | `Взрослые/Дети/Юниоры` | `text` | да у услуг | contract | CONFIRMED REUSE | MR mapping | MB-V06 |
| `payment_type` | тип оплаты | contract / M | `Предоплата/Рекарринг/Услуга` | `text` | нет | movement/KPI | CONFIRMED REUSE | MR mapping | MB-V06 |
| `product_id` | продукт | contract/service | stable product key | `text` | да | movement | CONFIRMED REUSE | MR mapping | orphan |
| `club_access_type` | локальный/сетевой | contract/product | эталонная MR-логика | `text` | да | contract | CONFIRMED REUSE | MR mapping | coverage |
| `access_time_type` | время доступа | product/index | эталонная MR-логика | `text` | да | contract | CONFIRMED REUSE | MR mapping | coverage |
| `contract_duration_category` | разрез длительности | `effective_duration_days` | presentation bucket; точные подписи формируются в Power BI | `numeric` source + Power BI label | да | KPI unit | CONFIRMED consumer / no new source | board PBIT | MB-V01 |

## Производные меры Power BI

| Мера | Формула | Статус |
|---|---|---|
| `Поступления` | `SUM(receipt_amount_net)` + утверждённые membership-услуги | CONFIRMED REUSE |
| `Количество` | один предоплатный контракт или одна группа `contract × payment_period` рекарринга | CONFIRMED REUSE |
| `Средняя цена контракта` | `SUM(calculation_price) / Количество` | CONFIRMED REUSE |
| `Продолжительность` | `AVERAGE(effective_duration_days) / 30.42` по тому же KPI-набору | CONFIRMED REUSE |
| `Средняя цена месяца` | `Средняя цена контракта / Продолжительность` | CONFIRMED REUSE |
| планы, прошлый год, отклонения, доли, MTD/YTD | DAX над общими фактами и внешними планами | CONFIRMED Power BI boundary |
| факторные компоненты | формулы из `membership_board.md` | CONFIRMED Power BI boundary |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| все источники `membership_receipts` | факты и измерения членства | CONFIRMED REUSE / PARTIALLY VALIDATED — SV-083 | source catalogs + PBIT comparison + SV-083 |
| текущий и среднесрочный планы | плановые сравнения | CONFIRMED external Power BI facts | оба PBIT |
| годовой план (`Бюджет24 в 1С`) | база `план годовой` | CONFIRMED external Power BI fact | board PBIT |
| `___Итого по сети` | calculated performance aggregate | CONFIRMED implementation artifact, not source of truth | board PBIT + user decision |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Источники из `source_objects` | новых источников 1С нет; набор совпадает с `membership_receipts` | CONFIRMED |
| Продукты из `data_products` | detailed membership domain полностью покрывает board KPI; group summary слишком грубый | CONFIRMED |
| Правила из `business_rules` | BR-001/002/003/013/014/015/016; BR-008 не применяется | CONFIRMED |
| Сравнение гранулярности | пять KPI, роли дат и срезы совпадают с отчётом по поступлениям | CONFIRMED user decision + PBIT |
| Сравнение ключей | movement key и KPI-grain повторяют `membership_receipts`; рекарринг агрегирует движения по `contract × payment_period` | CONFIRMED REUSE / SV-096 |
| Сравнение семантики | общие KPI обязаны совпадать; board добавляет только presentation logic | CONFIRMED user decision |
| Решение | `REUSE` detailed membership domain and common dimensions; `NOT_APPLICABLE` для нового board-факта | CONFIRMED |
| Причина | отдельный факт дублировал бы расчёты и создал второй источник истины | CONFIRMED |
| Затронутые потребители | `Отчёт по поступлениям`, `Отчёт членство для правления`, `Свод выручка ГК`, `Титульный лист` | CONFIRMED |

## Риски и проверки

| Статус | Элемент | Риск / причина | Проверка |
|---|---|---|---|
| VALIDATION_PENDING | физические ключи и состояния | bounded keys/contract joins validated by SV-083; full domain and states inherit MR pending | MR-V01–MR-V12 |
| VALIDATION_PENDING | равенство KPI | board-PBIT содержит 26 отличающихся общих мер | MB-V01 |
| VALIDATION_PENDING | performance aggregate | может менять filter context и неаддитивные KPI | MB-V02/MB-V08 |
| VALIDATION_PENDING | внешние планы | несовместимый grain может размножить факт | MB-V03/MB-V04 |
| VALIDATION_PENDING | факторная сходимость | компоненты должны сходиться с общим отклонением | MB-V05 |
| REJECTED | отдельный PostgreSQL board-факт | дублирует домен поступлений | решение REUSE |
| REJECTED | перенос `___Итого по сети` как бизнес-источника | рассчитанный performance workaround | user decision 2026-07-31 |
| REJECTED | board-версии пяти KPI | расходятся с оперативным эталоном | user precedence decision |

## Учёт class-C критичности — 2026-08-13

Не требуется новое бизнес-решение. Реализация должна переиспользовать две
разные сущности `membership_receipts`: денежные движения и контрактные
KPI-единицы. `kpi_unit_key` рекарринга остаётся ключом ежемесячного платежа,
а не контракта; `metric_date` не заменяет `receipt_date`. Неаддитивные меры
вычисляются из детального домена и не берутся из агрегата `___Итого по сети`.
До product admission остаются физическая валидация ключей/состояний и MB-V01;
они не являются основанием менять BR-015, BR-016 или current state/sign cases.
