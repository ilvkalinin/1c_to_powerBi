# Data contract: «Поступления по членству»

Статус: `STAGE 3 PRODUCT ADMISSION IN PROGRESS / DDL-DML NOT APPROVED / SHARED SOURCE VALIDATION COMPLETE — SV-083, SV-096, SV-112—SV-130`.

## Объекты

| Объект | Таблица Power BI | Grain / ключ |
|---|---|---|
| `mart.membership_receipt_movement` | `Поступления` | current-M receipt group / полный natural key с `UNIQUE NULLS NOT DISTINCT`; raw key SV-130 остаётся source control |
| `mart.membership_contract_kpi_unit` | `Контрактные KPI` | контракт предоплаты или ежемесячный recurring payment / `kpi_unit_key` |

Оба объекта — Import, ежедневный bounded rebuild BR-003 до 08:30. Надёжного
watermark нет. Планы остаются внешними Power BI-фактами. Решение пользователя
2026-08-19: достижение SLA «данные доступны к 08:30 МСК» проверяется только
при приёмке созданных витрин и их расписания обновления; до Stage 3 оно не
является source-side блокером.

## Движение поступления

| Поля | Целевые типы | Роль / видимость |
|---|---|---|
| `source_kind`, `source_object`, `source_group_recorder_id`, `source_group_line_no` | text, text, text, integer | branch и technical drivers current-M key; physical raw key нужен только неагрегированной service-ветке; скрыть |
| `source_stage_id`, `purchase_type_id`, `membership_kind_id`, `club_access_type_id` | text | technical IDs exact M-group; скрыть |
| `receipt_date` | date | активный FK календаря |
| `contract_id`, `client_key` | text | technical, скрыть |
| `movement_kind`, `recorder_type` | smallint, text | source classification, скрыть/срез |
| `amount_raw`, `amount_signed`, `co_access_amount`, `receipt_amount_net` | numeric | raw скрыть; net аддитивен |
| `service_group` | text | срез membership-услуг |
| `movement_club_id`, `access_club_id`, `sales_point_club_id`, `reporting_club_id` | text | role-playing club IDs; скрыть |
| `manager_id`, `product_id` | text | FK; скрыть |
| `payment_type`, `payment_source`, `super_stage`, `product_age_category` | text | срезы |

## Контрактная KPI-единица

| Поля | Целевые типы | Роль / видимость |
|---|---|---|
| `kpi_unit_key`, `kpi_unit_kind` | text | ключ/тип; key скрыть |
| `metric_date` | date | активный FK календаря |
| `contract_id`, `client_key`, `payment_period` | text, text, integer | technical; скрыть; рекарринг агрегируется по `contract_id × payment_period` |
| `access_club_id`, `sales_point_club_id`, `manager_id`, `product_id` | text | FK; скрыть |
| `contract_activation_date`, `contract_start_date`, `contract_end_date` | date | attributes; end — неактивная роль даты |
| `contract_term_days`, `free_freeze_before_activation_days`, `effective_duration_days` | numeric | helpers; не суммировать |
| `source_stage`, `super_stage`, `payment_type`, `payment_source` | text | срезы |
| `product_age_category`, `purchase_type`, `membership_kind`, `club_access_type`, `access_time_type`, `access_zone` | text | срезы |
| `list_contract_price` | numeric | KPI amount; не суммировать без unit filter |
| `calculation_mode` | text | classification, скрыть |

Технические drivers exact M-группы (`accounting_analytics_text`,
`source_product_name`, `source_product_freeze_days`, `source_object`,
`source_stage_id`, `purchase_type_id`, `membership_kind_id`,
`club_access_type_id`) скрыты, участвуют только в unique key и не являются
пользовательскими срезами. Их отображаемые классификации не заменяют IDs в
ключе. Все колонки mapping,
относящиеся только к одному grain, размещаются только в
соответствующем объекте; смешанная строка запрещена. `metric_date` у services
не создаётся, услуги отсутствуют в KPI-unit.

Объекты контракта не повторяют calculated tables Power BI. «Таблица активных
контрактов» — потребительский фильтр старой модели; `___Итого по сети` — её
performance workaround. Оба заменяются использованием этих двух общих фактов
и не получают физических аналогов.

## Связи и меры

Календарь поступления связан с движением; календарь KPI — с `metric_date`;
`contract_end_date` использует неактивную role-playing связь. Клуб доступа,
клуб продажи, менеджер, продукт, суперстаж, возраст продукта, тип оплаты и
канал фильтруют применимые факты `1:*`, single direction. Fact-to-fact и M2M
запрещены.

PostgreSQL рассчитывает signs, net, unit key, duration, classifications и
цены. DAX: `Поступления всего`, distinct `Количество`, средняя цена,
продолжительность/30.42, средняя цена месяца, LY/YTD. Приёмка следует
MR-V01…MR-V12: keys, signs, services scope, freeze/price joins, role dates,
manager/sales-club propagation, rerun и SLA.
