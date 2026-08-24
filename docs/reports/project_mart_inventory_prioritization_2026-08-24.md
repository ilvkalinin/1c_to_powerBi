# Инвентаризация и приоритизация витрин проекта

Статус: `COMPLETE / READ-ONLY PORTFOLIO REVIEW`.

Дата среза: 2026-08-24.

## Метод и граница

Текущий физический статус определён по первичному execution evidence и
`report_checkpoint_ledger.tsv`, а состав и grain — по
[`data_products`](../catalogs/data_products.md). Исторические отчёты с
формулировкой «implementation deferred» на дату до фактической загрузки не
переписываются как будто это были текущие статусы.

Проверка не обращалась к VM-1/VM-2, не запускала Stage 2 controls и не
меняла Power BI, DDL/DML или бизнес-правила.

## Исполненные физические продукты

В каталоге 23 реализованные записи, соответствующие 26 явно названным
объектам: несколько записей содержат fact+bridge либо core+child. Это не
означает, что 23 отчёта Power BI уже полностью переключены на PostgreSQL:
один physical product может обслуживать несколько отчётов, а часть
report-level Power BI-логики сознательно остаётся вне слоя витрин.

| Домен | Реализованные объекты | Подтверждение |
|---|---|---|
| Клиенты и посещения | `client_base_daily`, `visit_client_day` | initial load, source-to-target checks и rerun закрыты |
| Тренировки, планы и расписание | `ip_training_daily`, `dpfu_plan_assignment`, `prebooking_state_event`, `group_lesson`, `lesson_room_slot_5m` | initial BR-003 loads validated |
| Доходы и членство | `ancillary_revenue_movement`, `v_dpfu_ancillary_revenue`, `v_reception_revenue`, `ip_revenue_daily`, `revenue_group_summary_daily`, `membership_receipt_movement`, `membership_contract_kpi_unit` | source/target reconciliation и rerun подтверждены в соответствующих admission evidence |
| CRM и обращения | `crm_interaction`, `crm_interaction_phone`, `feedback_interaction`, `club_day_metrics`, `v_sales_interaction`, `v_feedback_interaction`, `v_guest_tour` | CRM-BR032 initial load и rerun: 1 519 900 / 1 002 750 / 154 741 / 8 590 строк; все controls passed |
| Воронки | `marketing_funnel_task`, `marketing_funnel_task_contract`, `fitness_leads_funnel_task`, `fitness_leads_funnel_task_service` | MF-R01—R06 и FL-R01—R06 passed with zero deviations |
| Администратор | `administrator_card_gymmy_daily` | initial BR-003 load validated |

### Исправленное расхождение

`data_products` ранее отставал от primary CRM execution evidence: core,
phone child, compact feedback fact, `club_day_metrics` и три views были
загружены и прошли rerun 2026-08-21, но были помечены как deferred. Каталог
и ADR-0016 приведены к доказанному статусу; существующие незакоммиченные
изменения CRM mapping и contract сознательно не включались в этот пакет.

`club_day_metrics` — уже реализованный узкий additive denominator для
«Отчёта по обращениям». Он не подменяет отдельную семантику групповых
программ в отчётах посещаемости. Добавлена отсутствовавшая в каталоге строка
`mart.feedback_interaction`.

## Полный список не реализованных продуктов

Ниже перечислены все 18 оставшихся catalog entries. Их порядок — не
автоматическое разрешение на реализацию: любая Stage 3 admission или новая
валидация остаётся самостоятельным пакетом.

| Приоритет | Продукт | Текущий статус | Основание и следующая безопасная граница |
|---|---|---|---|
| 1 | `mart.new_first_visit` | DESIGNED; source validation validated with preserved ties | Для «Новички и гостевые визиты»; CRM core уже реализован. Нужен отдельный Stage 3 planning с PII/access boundary и exact DDL/reconciliation, без новой методики tie handling. |
| 1 | `mart.guest_visit_conversion` | DESIGNED; validated ACCUNIQ and 0–44 day rules | Та же report wave; остаётся отдельным guest-date grain и не объединяется с CRM tour или first visit. Нужен тот же bounded planning package. |
| 2 | `mart.club_attendance_hourly` | DESIGNED; SV-065/SV-067 partially validated | `client_base_daily` уже реализован, но нужны exact historical controls и план full rebuild; шкафчики остаются Power BI-only. |
| 2 | `mart.preparation_renewal_checkpoint` | DESIGNED; SV-077 partially validated | Переиспользует contract/visit evidence, но joins и freeze intervals сохраняют current-rule risks. Сначала read-only planning/controls. |
| 2 | `mart.newcomer_engagement_milestone` | DESIGNED; SV-075 partially validated | Зависит от contract/freeze/child package semantics; не смешивается с client-day. Сначала bounded technical planning. |
| 2 | `mart.newcomer_engagement_second_month` | DESIGNED; SV-076 partially validated | Второй месяц имеет отдельную temporal semantics; preserved legacy `RANK` ties не менять. Сначала bounded technical planning. |
| 3 | `mart.unconfirmed_service_debt_movement` | DESIGNED; SV-089 partially validated | `visit_client_day` можно reuse только как cohort; as-of и document branches ещё не закрыты. Нужен отдельный read-only source-control package. |
| 3 | `mart.v_administrator_bookings_daily` | PROPOSED; technical validation blocked | Есть общий revenue fact, но booking-to-movement cardinality и суммы не подтверждены; нельзя создавать view до этой проверки. |
| 3 | `mart.client_base_snapshot` | ACCEPTED; SV-069 partially validated | Daily fact не заменяет редкие snapshot-строки; требуются точные package/visit/state controls и output representation. |
| 3 | `mart.client_base_retention` | ACCEPTED; SV-069 foundation only | Имеет иной baseline-cohort grain, поэтому не является расширением daily/snapshot; нужно отдельное retention evidence. |
| 4 | `mart.children_package_sale` | DESIGNED; technical validation blocked | Child × package × receipt и return semantics требуют завершить технические checks; общий revenue fact не утверждён как замена. |
| 4 | `mart.promo_application` | DESIGNED; technical validation required | Discount/gift и 45-day outcomes имеют отдельные grains; нужна source validation до planning. |
| 4 | `mart.contract_usage` | PROPOSED; technical validation blocked | Нужен для %Renew; frozen semantics явно не совместима с renewal-management. |
| 4 | `mart.renewal_management_contract` | PROPOSED; technical validation blocked | Широкий current-contract продукт с Renew, PII и CRM; не reuse `contract_usage`. |
| 4 | `mart.fitness_funnel_client_start` | DESIGNED; SV-079 partially validated | Требует cohort dedupe client-start; не расширяет contract facts. |
| 4 | `mart.fitness_funnel_client_outcome` | DESIGNED; SV-079 foundation only | Source key pending; outcomes не получают contract attribution без отдельного правила. |
| 4 | `mart.employee_activity_interval` | DESIGNED; technical validation required | Нет подтверждённого technical event key; interval hours нельзя смешивать с revenue/plans. |
| 4 | `mart.employee_presence_day` | DESIGNED; technical validation required | Separate access-control denominator; не выводится из activity fact. |

## Рекомендованный следующий пакет

Первой следующей волной рекомендуется только `STAGE_3_PLANNING` для
«Новички и гостевые визиты»: `mart.new_first_visit` и
`mart.guest_visit_conversion`. Причины: это два наиболее подготовленных
не реализованных продукта с validated source controls, уже реализованным CRM
core и без разрешённой замены их grain. Пакет должен оставаться planning-only:
проверить exact target object set, PII role, full-rebuild/reconciliation plan
и отсутствие новых бизнес-решений; DDL/DML и Power BI switch не включать.

Критерий закрытия такого следующего пакета — immutable reviewed plan для
ровно этих двух facts с зафиксированными controls, rollback boundary и
отдельно указанными remaining risks, готовый к единому admission approval.

## Не изменившиеся ограничения

- BR-003 и full rebuild остаются текущей моделью; daily incremental не
  подразумевается ни для одного отложенного продукта.
- Внешние Excel и Power Query не включаются.
- `CLOSED_CHECKPOINT` в ledger не даёт права повторить прошлую validation;
  повтор возможен только при новом зафиксированном trigger.
- Продукты с разным grain не объединяются лишь из-за общего источника или
  общего названия отчёта.
