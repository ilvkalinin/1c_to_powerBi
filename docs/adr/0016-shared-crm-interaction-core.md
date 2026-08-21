# ADR-0016: общий факт CRM-взаимодействий

- Статус: `TECHNICAL SQL REVIEW IN PROGRESS / IMPLEMENTATION DEFERRED`
- Дата: 2026-08-03
- Отчёты: №12 «Загрузка ОП», №20 «Новички и гостевые визиты», №21 «Отчёт по обращениям»

## Контекст

Три отчёта используют одно событие `Reference67.ID`, задачу `Reference106`,
исполнителя, клиента и CRM-классификации. Различаются отборы и product-specific
outcomes. Телефония и комментарии могут иметь несколько строк на одно
взаимодействие и не могут присоединяться к core без multiplication.

## Решение

В следующем отдельно одобренном implementation package создать минимальный
физический набор с grain:

> одно взаимодействие `Reference67.ID`.

`mart.crm_interaction.interaction_id` — логический ключ. Дополнительно нужны
две fact-children: `mart.crm_interaction_phone` с ключом
`(interaction_id, phone_reference_id, phone_event_id)` и
`mart.crm_interaction_comment` с ключом `(interaction_id, comment_id)`.
Кадровые интервалы остаются source-side `EXISTS`, без репликации. Дочерние
таблицы сохраняют required PBIT multiplicity; они не меняют core grain. На
локальной VM создать обычные views без materialized views:

- `mart.v_sales_interaction` — отбор воронок/должностей «Загрузки ОП»;
- `mart.v_feedback_interaction` — обратная связь, комментарий и отработка;
- `mart.v_guest_tour` — туры и report-specific 44-дневные outcomes.

Дневной знаменатель обращений добавляется в существующий
`mart.club_day_metrics` как `visit_event_count`; новый факт посещений не
создаётся. Поля PII выдаются только report-specific views с подтверждённым
потребителем и политикой BR-017.

Выбран физический core с двумя малыми factual children из-за повторного
использования и обязательной PBIT multiplicity. Постоянный staging не
создаётся. Materialized views не выбираются без измерений; обычные локальные
views не повторяют чтение VM-1.

## Обновление и Power BI

Частота обновления и способ loading не утверждены этой технической проверкой.
До отдельного approved incremental package допустим только измеренный
full rebuild; ежедневный SLA и watermark не заявляются.

Для первого релиза report-compatible `mart.v_sales_interaction` сохраняет
текущий `LEFT JOIN Reference67 → InfoRg7146`: одна interaction с несколькими
phone rows появляется несколькими строками, как в Power Query. SV-026
подтверждает 3 103 таких interaction за 2026 год; по решению пользователя
2026-08-05 каждая phone row является отдельным звонком менеджера. Это
подтверждённая бизнес-семантика, а не методическая ошибка.

PostgreSQL выполняет fixed CRM-классификации и детерминированную нормализацию.
DAX считает медиану, нормативную загрузку, доли, сроки ответа и конверсии.
Плановые Excel/Google Sheets остаются отдельными фактами Power BI.

## Риски

Read-only technical review 2026-08-21 подтвердил source `bytea` IDs,
`timestamp without time zone`, 0 missing tasks in 342 824 July core rows,
phone-child candidate key without nulls/duplicates in its bounded sample and
331 662 July comments with non-null comment ID. The same review observed 1
earliest-follow-up tie; no same-interaction comment timestamp tie appeared in
the full July control. Views nevertheless order by timestamp plus physical ID
as an explicit reproducibility safeguard. Guest outcomes still need an
explicit policy for legacy ACCUNIQ and contract ties before exact SQL is
approved.

Read-only PBIT reconciliation 2026-08-21 выявил sales final `Distinct` и роль
«Ведущий менеджер», feedback grouping без `Reference67.ID`, а в guest-tour —
direct phone join и отдельную report date. Compatibility rules resolved by
BR-018, the prior phone-row user decision and approved PBIT: core-grain не
меняется, а view воспроизводят эти различия. Это не разрешает DDL/DML. Детали
— в [`CRM admission preparation`](../reports/crm_interaction_admission_preparation_2026-08-21.md).

## Доказательства

- [Mapping загрузки ОП](../mappings/sales_interactions.md)
- [Mapping обращений](../mappings/calls_report.md)
- [Mapping новичков/гостей](../mappings/newcomer_guest_visits.md)
