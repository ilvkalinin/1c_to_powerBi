# Data contract: маркетинговая «Воронка»

Статус: `PLANNED NEW TWO-FACT CONTRACT / BR-003 RETENTION CONFIRMED / NO DDL OR DML`.

Модель использует два минимальных PostgreSQL-факта:
`mart.marketing_funnel_task` для task core и
`mart.marketing_funnel_task_contract` для candidate `task × contract` с
отдельным qualification flag BR-020.

Потребитель использует поля: `task_id`, `task_code`, `task_date`, даты
закрытия, `funnel_id/name`, `club_id`, network/cluster из dimension,
`client_key/code`, `tenure_type`, campaign ID/name/parent,
`unsuccessful_reason`, `funnel_stage_name`, raw/final first interaction,
`traffic_direction`, contract ID/name, `activation_date`, возраст/тип оплаты/
длительность контракта, `task_count` и `contract_count = 1` на каждой связи,
прошедшей BR-020. Целевые
типы: IDs `text`, даты `date/timestamp`, counts `smallint`; технические ID и
client key скрыты.

`task` фильтрует `task_contract` отношением `1:*`, single direction. Bridge
имеет `is_conversion_qualified` и `contract_count`: DAX мер «Абонементы факт»
фильтрует первое/суммирует второе, тогда как current DAX накопленного трафика
использует candidate contract-client rows до выбранного месяца. Календарь,
клуб, воронка, кампания и тип взаимодействия фильтруют task fact; contract
slices фильтруют только bridge measures. Excel-планы остаются отдельными
фактами через общие измерения. PostgreSQL поставляет task core и атрибуцию
контракта; DAX считает задания, контракты, конверсию, накопленный трафик и
план-факт.

SV-080 подтверждает task core для reuse, но не one-to-one bridge: 100 строк
bridge соответствуют 36 заданиям, 21 из них имеет несколько контрактов.
BR-020 прямо задаёт единицу: каждая связь считается после условия
`activation_date >= task_created_at` и history с 2024-01-01; global dedup
абонемента запрещён. Физические объекты не создавались.

Приёмка Stage 3: уникальный target task, task→contract bridge без
размножения, контрольные меры, rerun и SLA созданной витрины. Внешние plans и
network/cluster остаются в границе текущей модели Power BI.
