# ADR-0016: общий факт CRM-взаимодействий

- Статус: `DESIGNED / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-084, SV-087, SV-088 / IMPLEMENTATION DEFERRED`
- Дата: 2026-08-03
- Отчёты: №12 «Загрузка ОП», №20 «Новички и гостевые визиты», №21 «Отчёт по обращениям»

## Контекст

Три отчёта используют одно событие `Reference67.ID`, задачу `Reference106`,
исполнителя, клиента и CRM-классификации. Различаются отборы и product-specific
outcomes. Телефония и комментарии могут иметь несколько строк на одно
взаимодействие и должны нормализоваться до core-grain.

## Решение

Создать физическую таблицу `mart.crm_interaction` с grain:

> одно взаимодействие `Reference67.ID`.

`interaction_id` — логический ключ. Телефонные строки, комментарии и кадровые
интервалы агрегируются/проверяются source-side до присоединения к core. На
локальной VM создать обычные views без дополнительного хранения:

- `mart.v_sales_interaction` — отбор воронок/должностей «Загрузки ОП»;
- `mart.v_feedback_interaction` — обратная связь, комментарий и отработка;
- `mart.v_guest_tour` — туры и report-specific 44-дневные outcomes.

Дневной знаменатель обращений добавляется в существующий
`mart.club_day_metrics` как `visit_event_count`; новый факт посещений не
создаётся. Поля PII выдаются только report-specific views с подтверждённым
потребителем и политикой BR-017.

Выбрана физическая core-таблица из-за повторного использования и частого
refresh «Загрузки ОП». Постоянный staging не создаётся. Materialized views
не выбираются без измерений; обычные локальные views не повторяют чтение VM-1.

## Обновление и Power BI

Core обновляется восемь раз в день `08–22` для «Загрузки ОП»; дневные
потребители используют последний согласованный refresh. До надёжного
watermark применяется атомарный пересчёт ограниченного BR-003 горизонта либо
подтверждённого изменяемого окна после server validation.

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

SV-026 подтверждает 3 103 interaction с 2–3 phone rows за 2026 год; это
отдельные звонки в рамках одного взаимодействия и report-view сохраняет их
отдельными строками. SV-088 применяет это evidence к feedback-view; HTML
cardinality, first follow-up/comment tie-break, states и контрольные значения
остаются `VALIDATION_PENDING`.

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
