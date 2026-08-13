# Data contract: маркетинговая «Воронка»

Статус: `DESIGNED REUSE / IMPLEMENTATION DEFERRED / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED — SV-080`.

Отдельного PostgreSQL-факта нет. Модель REUSE использует
`mart.fitness_leads_funnel_task` для task core и его логическую проекцию
`task × qualified contract` для метрики «Абонементы факт».

Потребитель использует поля: `task_id`, `task_code`, `task_date`, даты
закрытия, `funnel_id/name`, `club_id`, network/cluster из dimension,
`client_key/code`, `tenure_type`, campaign ID/name/parent,
`unsuccessful_reason`, `funnel_stage_name`, raw/final first interaction,
`traffic_direction`, contract ID/name, `activation_date`, возраст/тип оплаты/
длительность контракта, `task_count` и `contract_count = 1` на каждой связи,
прошедшей BR-020. Целевые
типы: IDs `text`, даты `date/timestamp`, counts `smallint`; технические ID и
client key скрыты.

Календарь, клуб, воронка, кампания и тип взаимодействия фильтруют факт `1:*`,
single direction. Excel-планы остаются отдельными фактами через общие
измерения. PostgreSQL поставляет task core и атрибуцию контракта; DAX считает
задания, контракты, конверсию, накопленный трафик и план-факт.

SV-080 подтверждает task core для reuse, но не one-to-one bridge: 100 строк
bridge соответствуют 36 заданиям, 21 из них имеет несколько контрактов.
BR-020 прямо задаёт единицу: каждая связь считается после условия
`activation_date >= task_created_at` и history с 2024-01-01; global dedup
абонемента запрещён. Физические объекты не создавались.

Приёмка: уникальный task, доказанный task→contract bridge, distinct contract
без размножения, plan grain, network/cluster, контрольные меры и SLA.
