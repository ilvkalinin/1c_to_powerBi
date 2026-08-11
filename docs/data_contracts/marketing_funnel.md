# Data contract: маркетинговая «Воронка»

Статус: `DESIGNED REUSE / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION PARTIALLY VALIDATED (SV-080)`.

Отдельного PostgreSQL-факта нет. Модель REUSE
`mart.fitness_leads_funnel_task` (ADR-0011) на grain одного CRM-задания.

Потребитель использует поля: `task_id`, `task_code`, `task_date`, даты
закрытия, `funnel_id/name`, `club_id`, network/cluster из dimension,
`client_key/code`, `tenure_type`, campaign ID/name/parent,
`unsuccessful_reason`, `funnel_stage_name`, raw/final first interaction,
`traffic_direction`, contract ID/name, `activation_date`, возраст/тип оплаты/
длительность контракта, `task_count` и validated `contract_count`. Целевые
типы: IDs `text`, даты `date/timestamp`, counts `smallint`; технические ID и
client key скрыты.

Календарь, клуб, воронка, кампания и тип взаимодействия фильтруют факт `1:*`,
single direction. Excel-планы остаются отдельными фактами через общие
измерения. PostgreSQL поставляет task core и атрибуцию контракта; DAX считает
задания, контракты, конверсию, накопленный трафик и план-факт.

Приёмка: уникальный task, доказанный task→contract bridge, distinct contract
без размножения, plan grain, network/cluster, контрольные меры и SLA.
