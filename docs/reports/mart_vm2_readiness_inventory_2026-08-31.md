# Инвентаризация витрин VM-2 — 2026-08-31

Статус: `READ_ONLY INVENTORY`. Время среза: 2026-08-31, VM-2.

Проверены системный каталог PostgreSQL, точный `COUNT(*)` и `MIN/MAX` одной
подтверждённой бизнес-даты (или технического watermark) каждой физической
витрины. Это доказывает наличие и фактический горизонт данных на VM-2, но не
повторяет source-to-target reconciliation: его evidence указано в каталоге и
предыдущих пакетах. «До» ниже — максимум выбранной бизнес-даты, а не дата
запуска загрузчика; для current-state витрин он может быть будущим по самой
модели.

| Объект VM-2 | Строк | Поле горизонта | Данные до | Статус для Power BI | Следующий безопасный шаг |
| --- | ---: | --- | --- | --- | --- |
| `administrator_bookings_daily` | 3,139 | `lesson_date` | 2026-08-29 | ACCEPTED; не переключена в PBI | display dimensions, format contract, PBI reconciliation |
| `administrator_card_gymmy_daily` | 8,057 | `event_date` | 2026-08-19 | ACCEPTED | согласовать freshness, затем standard PBI package |
| `ancillary_revenue_movement` | 659,403 | `service_date` | 2026-08-20 | ACCEPTED | refresh-order shared fact, затем standard PBI package |
| `children_package_sale` | 19,412 | `sale_date` | 2026-08-27 | ACCEPTED | согласовать freshness, затем standard PBI package |
| `client_base_daily` | 1,401,982 | `report_date` | 2026-08-26 | ACCEPTED | current refresh and PBI contract |
| `client_base_retention` | 1,101,391 | `report_date` | 2026-08-24 | ACCEPTED | current refresh and PBI contract |
| `client_base_snapshot` | 1,590,169 | `report_date` | 2026-08-24 | ACCEPTED | current refresh and PBI contract |
| `club_attendance_hourly` | 5,966,022 | `visit_date` | 2026-08-24 | ACCEPTED | current refresh; full rebuild is not daily SLA |
| `club_day_metrics` | 8,590 | `event_date` | 2026-08-20 | ACCEPTED | refresh CRM chain, then PBI contract |
| `contract_usage` | 218,376 | `membership_end_date` | 2300-05-21 sentinel | ACCEPTED | confirm report-date role; do not treat this max as freshness |
| `crm_interaction` | 1,519,900 | `report_date` | 2026-08-20 | ACCEPTED | refresh CRM chain, PII role, PBI reconciliation |
| `crm_interaction_phone` | 1,002,750 | `phone_at` | 2026-08-20 21:15 | ACCEPTED | refresh CRM chain, PII role, PBI reconciliation |
| `dpfu_plan_assignment` | 525,593 | `plan_date` | 2026-08-27 | ACCEPTED | current refresh and PBI contract |
| `employee_activity_interval` | 798,604 | `activity_date` | 2026-08-27 | ACCEPTED | current refresh; full rebuild is not daily SLA |
| `employee_presence_day` | 351,327 | `presence_date` | 2026-08-28 | ACCEPTED | current refresh and PBI contract |
| `feedback_interaction` | 154,741 | `created_at` | 2026-08-20 23:50 | ACCEPTED | refresh CRM chain and PBI reconciliation |
| `fitness_funnel_client_outcome` | 1,037,064 | `outcome_date` | 2026-08-28 | ACCEPTED | current refresh and fitness-funnel PBI package |
| `fitness_funnel_client_start` | 231,490 | `membership_start_date` | 2026-08-27 | ACCEPTED | current refresh and fitness-funnel PBI package |
| `fitness_leads_funnel_task` | 166,722 | `task_date` | 2026-08-24 | ACCEPTED | current refresh and bridge-safe PBI model |
| `fitness_leads_funnel_task_service` | 27,131 | `service_date` | 2026-08-24 | ACCEPTED | current refresh and bridge-safe PBI model |
| `group_lesson` | 297,280 | `lesson_start_at` | 2026-08-26 21:30 | ACCEPTED | current refresh and PBI contract |
| `guest_visit_conversion` | 103,974 | `guest_visit_date` | 2026-08-24 | ACCEPTED | current refresh and PBI contract |
| `ip_revenue_daily` | 1,253 | `revenue_date` | 2026-08-17 | ACCEPTED | current refresh and PBI contract |
| `ip_training_daily` | 141,260 | `training_date` | 2026-08-27 | ACCEPTED | current refresh and PBI contract |
| `lesson_room_slot_5m` | 5,393,201 | `slot_start_at` | 2026-08-26 21:50 | ACCEPTED | current refresh and PBI contract |
| `marketing_funnel_task` | 865,891 | `task_date` | 2026-08-24 | ACCEPTED | current refresh and PBI contract |
| `marketing_funnel_task_contract` | 341,704 | `activation_date` | 2029-08-31 | ACCEPTED | confirm report-date role; max is not freshness |
| `membership_contract_kpi_unit` | 150,892 | `metric_date` | 2026-08-20 | ACCEPTED | current refresh and PBI contract |
| `membership_receipt_movement` | 293,577 | `receipt_date` | 2026-08-20 | ACCEPTED | current refresh and PBI contract |
| `new_first_visit` | 95,984 | `first_visit_date` | 2026-08-24 | ACCEPTED | current refresh and PBI contract |
| `newcomer_engagement_milestone` | 364,226 | `checkpoint_date` | 2026-08-26 | ACCEPTED | current refresh and PBI contract |
| `newcomer_engagement_second_month` | 153,953 | `month_of_engagement` | 2026-08-01 | ACCEPTED | agree month-close freshness, then PBI contract |
| `prebooking_state_event` | 2,389,981 | `state_event_at` | 2026-08-14 16:03 | ACCEPTED | current refresh and PBI contract |
| `preparation_renewal_checkpoint` | 707,571 | `checkpoint_date` | 2026-08-26 | ACCEPTED | current refresh and PBI contract |
| `promo_application` | 132,814 | `application_date` | 2026-08-28 | ACCEPTED | current refresh and PBI contract |
| `renewal_management_contract` | 240,949 | `membership_end_date` | 2027-01-31 | ACCEPTED | parent refresh before observation; max is horizon, not freshness |
| `renewal_management_contract_observation` | 248,749 | `observed_at` | 2026-08-31 09:34+03 | ACCEPTED | scheduled parent→append chain and as-of PBI contract |
| `revenue_group_summary_daily` | 25,339 | `revenue_date` | 2026-08-20 | ACCEPTED | refresh dependencies, then PBI contract |
| `unconfirmed_service_debt_movement` | 1,206,628 | `debt_event_at` | 2026-08-27 22:00 | ACCEPTED | current refresh and PBI contract |
| `v_dpfu_ancillary_revenue` | 508,639 | `service_date` | 2026-08-20 | ACCEPTED view | refresh shared fact, then PBI contract |
| `v_feedback_interaction` | 154,741 | `created_date` | 2026-08-20 | ACCEPTED view | refresh CRM chain and PBI reconciliation |
| `v_guest_tour` | 97,252 | `report_date` | 2026-08-20 | ACCEPTED view | refresh CRM chain and PBI reconciliation |
| `v_reception_revenue` | 150,764 | `revenue_date` | 2026-08-20 | ACCEPTED view | refresh shared fact, then PBI contract |
| `v_sales_interaction` | 1,487,889 | `interaction_date` | 2026-08-20 | ACCEPTED view | refresh CRM chain, PII role and PBI reconciliation |
| `visit_client_day` | 7,172,391 | `visit_date` | 2026-08-21 | ACCEPTED | current refresh and PBI contract |

## Итог

- На VM-2 присутствуют все 42 каталожные позиции; для каждой найдены
  подтверждённые acceptance-evidence.  В частности, обе физические витрины
  фитнес-воронки приняты 2026-08-28; старые статусы каталога были исправлены.
- Данные большинства текущих витрин заканчиваются 14–29 августа. Это не
  дефект самой витрины, но исключает заявление о текущей ежедневной свежести.
- Общий следующий проектный шаг: один операционно-BI пакет, который сначала
  фиксирует допустимую свежесть и порядок refresh зависимостей, затем создаёт
  ограниченные reader roles, проверяет contracts/relationships/M-DAX и только
  после этого переключает отчёты.
