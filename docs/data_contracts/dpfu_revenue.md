# Data contract: «Выручка ДПФУ»

Статус: `DESIGNED COMPOSITE MODEL / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

Модель REUSE `mart.ancillary_revenue_movement`, `mart.ip_training_daily`,
`mart.ip_revenue_daily` и `mart.dpfu_plan_assignment` по ADR-0005/0012.

Основной факт содержит дату, source kind, club/client/employee/service/activity/
format IDs, отображаемые имена, client category, payment/calculation/age
categories, `service_quantity numeric` и `revenue_amount numeric`. Внешняя
`service_group` не входит в PostgreSQL и добавляется малым справочником Power
BI. План содержит date/club/activity/employee/planned client, `planned_revenue`;
бюджетные количества/УЧК/регулярность остаются external. IP revenue содержит
date/club/service/amount.

Общие календарь, клуб, сотрудник, услуга, деятельность и формат фильтруют
применимые факты `1:*`, single direction. Fact-to-fact нет. PostgreSQL
рассчитывает signs и fixed categories; DAX — выручку, количество, УЧК,
регулярность, средний чек, ИП, MTD/LY и план-факт.

Приёмка: movement key, anti-overlap 7575/7646, source states/signs, client
distinct по клубу/сети, IP service link, plan key, контрольные суммы и SLA.

