# Data contract: «Отчёт по обращениям»

Статус: `DESIGNED / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-088`.

SV-088 переиспользует SV-024—SV-034 для CRM core: ключ interaction,
PK-side task dimensions и phone-row grain подтверждены source-side. Не
подтверждены HTML aggregation, exact feedback filters, first follow-up,
comment-update ties, visit denominator, rerun/SLA и independent Power BI
control values. Физические объекты не создавались.

## Факт обратной связи

| Параметр | Значение |
|---|---|
| Объект | `mart.v_feedback_interaction` над `mart.crm_interaction` |
| Таблица Power BI | `Обращения` |
| Grain / ключ | одно feedback-взаимодействие / `feedback_interaction_id` |
| Дата | `created_date` |
| Обновление | ежедневно до 08:30; core может быть свежее |

Поля: `feedback_interaction_id text`, `task_id text`, `created_at timestamp`,
`created_date date`, `started_at/ended_at/planned_at timestamp`,
`resolution_days integer`, `resolution_bucket text`, пары ID/name темы, клуба,
воронки, подразделения, статуса, состояния, исполнителя и должности; client
ID/code/name/phone `text`; `tenure_type`, campaign ID/name, `channel_name`,
`regulated_interaction_name`, `cancellation_reason_name`, `comment_text`;
`comment_updated_at`, `first_followup_at`, `worked_at` timestamp;
`worked_flag boolean`, `response_minutes numeric`. NULL — по mapping. Все ID
и `task_id` скрыты; PII/comment видимы по BR-017.

## Знаменатель посещений

REUSE `mart.club_day_metrics` с колонкой `visit_event_count bigint` на grain
`(event_date, club_id)`. Она аддитивна и не заменяется distinct client-day.

Календарь и клуб фильтруют оба факта `1:*`, single direction; между фактами
связи нет. PostgreSQL рассчитывает deterministic comment/followup и buckets.
DAX считает distinct `comment_text × client_code`, медиану ответа, доли и
отношение к посещениям.

Приёмка: уникальный interaction, нормализованные phone/comment rows,
правильный earliest followup/comment, nonnegative resolution/response,
reconciliation visit count, отсутствие M2M, rerun и SLA.
