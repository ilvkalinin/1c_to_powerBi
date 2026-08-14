# Data contract: «Выручка ДПФУ»

Статус: `DESIGNED COMPOSITE MODEL / mart.ancillary_revenue_movement IMPLEMENTED / remaining products deferred`.

Модель REUSE `mart.ancillary_revenue_movement`, `mart.ip_training_daily`,
`mart.ip_revenue_daily` и `mart.dpfu_plan_assignment` по ADR-0005/0012.

Основной факт содержит дату, source kind, club/client/employee/service/activity/
format IDs, отображаемые имена, calculation/age categories,
`service_quantity numeric` и `revenue_amount numeric`. Внешняя
`service_group` не входит в PostgreSQL и добавляется малым справочником Power
BI. План содержит date/club/activity/employee/planned client, `planned_revenue`;
бюджетные количества/УЧК/регулярность остаются external. IP revenue содержит
date/club/service/amount.

Для `mart.ancillary_revenue_movement` первого релиза `client_key` и
`client_code` равны `Reference141X1._Code::text`. S3-ADMISSION-001 подтвердил
в квалифицированном факте ДПФУ 41 682 клиента без пустых или повторяющихся
кодов; исходный `bytea` ID клиента в Power BI не передаётся.

Общие календарь, клуб, сотрудник, услуга, деятельность и формат фильтруют
применимые факты `1:*`, single direction. Fact-to-fact нет. PostgreSQL
рассчитывает signs и fixed categories; DAX — выручку, количество, УЧК,
регулярность, средний чек, ИП, MTD/LY и план-факт.

`mart.dpfu_plan_assignment` хранит скрытый
`plan_line_discriminator` из `InfoRg6612.Fld6619` вместе с датой, клубом,
подразделением, сотрудником и плановым клиентом: без него текущий detail
grain не уникален. `Fld6619` не является вторым клиентским ключом.
Отображаемые имя сотрудника и формат тренировки nullable: идентификаторы
некоторых движений не имеют строки в текущих справочниках, но сами движения
и их суммы сохраняются.

Приёмка выполнена для текущих правил: movement key, anti-overlap 7575/7646,
source states/signs, client distinct по клубу/сети, IP service link, plan key
и контрольные суммы (SV-054–SV-056). SLA требует повторного измерения после
создания объектов Stage 3; baseline исходных запросов — SV-057.
