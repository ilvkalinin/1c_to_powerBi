# Полный review global gate — 2026-08-19

Статус: `STAGE3_PLANNING_AUTHORIZED / IMPLEMENTATION STILL BLOCKED`.

## Граница review

Review выполнен только по договорному scope и документированным целевым
продуктам. Он не выполняет SQL на источнике, не меняет согласованные
SQL/M/DAX-правила и не создаёт витрины. После явного подтверждения пользователя
2026-08-19 gate переведён только в режим планирования первой Stage-3 волны;
выбор runnable package, DDL и DML остаются заблокированными.

Проверены три реестра:

| Реестр | Ожидание | Фактический результат |
|---|---:|---:|
| Договорные отчёты | 31 | 31 |
| Соответствующие им Stage-2 checkpoints в ledger | 31 | 31, все `CLOSED_CHECKPOINT` |
| Целевые продукты `mart.*` | 38 | 38 |

Дополнительный Stage-2 checkpoint `lesson_room_slot_5m` относится к объекту,
а не к отдельному договорному отчёту; он тоже `CLOSED_CHECKPOINT`.

## Как читать прежние статусы

Исторические слова `PARTIALLY VALIDATED`, `VALIDATION_REQUIRED` и
`DECISION_REQUIRED` в старом реестре описывают первоначально найденные
риски. Они не дают права повторно запускать проверку и не отменяют позднее
доказательство или решение. Для данного review источником текущего статуса
являются, в следующем порядке: подтверждённое бизнес-правило, сохранённый
source-result, `.agents/report_checkpoint_ledger.tsv`, затем mapping/ADR/data
contract.

`CLOSED_CHECKPOINT` не означает, что объект уже создан. Он означает: для
первого релиза больше нет автоматически разрешённой source-side работы без
нового независимого триггера; обнаруженные legacy-риски сохраняются по BR-018,
а физический контракт, end-to-end rerun и SLA проверяются после создания
объекта.

## 31 договорный отчёт

| № | Report ID | Итог source review |
|---:|---|---|
| 1 | `kpi_fitness` | `CLOSED_CHECKPOINT`: текущие правила и общие факты сохранены; report-level приёмка — после создания зависимостей. |
| 2 | `newcomer_engagement` | `CLOSED_CHECKPOINT`: текущие contract/freeze/visit правила сохранены. |
| 3 | `newcomer_engagement_second_month` | `CLOSED_CHECKPOINT`: child/СПТ multiplicity и `RANK()` ties сохранены по BR-018. |
| 4 | `preparation_renewal` | `CLOSED_CHECKPOINT`: current state/interval/join правила сохранены. |
| 5 | `fitness_leads_funnel` | `CLOSED_CHECKPOINT`: current task/contract scope сохранён. |
| 6 | `employee_workload` | `CLOSED_CHECKPOINT`: нельзя выдумывать ключ или нормализовать overlap без нового триггера/решения. |
| 7 | `prebooking_control` | `CLOSED_CHECKPOINT`: legacy multiplicity и document/registry branches сохранены по BR-018. |
| 8 | `ip_training` | `CLOSED_CHECKPOINT`; физический IP-факт уже прошёл собственный admission. |
| 9 | `visits_fizkult` | `CLOSED_CHECKPOINT`: применяется единое определение посещения BR-025. |
| 10 | `lessons_schedule` | `CLOSED_CHECKPOINT`; slot-edge policy подтверждена BR-021, объект slot уже принят. |
| 11 | `fitness_funnel` | `CLOSED_CHECKPOINT`: текущая cohort/outcome семантика сохранена. |
| 12 | `sales_interactions` | `CLOSED_CHECKPOINT`: bounded source evidence сохранён; phone/role rules не меняются. |
| 13 | `membership_receipts` | `CLOSED_CHECKPOINT`: `contract × payment_period` и current sign/state domain подтверждены. |
| 14 | `promo_codes` | `CLOSED_CHECKPOINT`: legacy join multiplicity и DAX fallback сохранены по BR-018. |
| 15 | `children_package_sales` | `CLOSED_CHECKPOINT`: согласованный fallback для 38 строк — `0`; новых правил нет. |
| 16 | `renewal_management` | `CLOSED_CHECKPOINT`: current same-client/first-start rule сохранён. |
| 17 | `renew_contract_usage` | `CLOSED_CHECKPOINT`: current window и `COUNT(*)` сохранены. |
| 18 | `reception_revenue` | `CLOSED_CHECKPOINT`: атрибуция продавца не меняется без решения. |
| 19 | `administrator_bookings` | `CLOSED_CHECKPOINT`: document grain и current attribution сохранены. |
| 20 | `newcomer_guest_visits` | `CLOSED_CHECKPOINT`: ACCUNIQ scope/sign, outcome boundary и first-visit path доказаны; ties сохранены. |
| 21 | `calls_report` | `CLOSED_CHECKPOINT`: current denominator/CRM scope доказаны; rerun/SLA — после создания. |
| 22 | `visits_debt` | `CLOSED_CHECKPOINT`: BR-025 и as-of control доказаны; legacy filter сохранён как артефакт. |
| 23 | `visits_pushkinsky` | `CLOSED_CHECKPOINT`: общий visit/day scope и current categories сохранены. |
| 24 | `work_attendance` | `CLOSED_CHECKPOINT`: 730 дней дневной КБ и четыре exact anchor-сверки доказаны. |
| 25 | `administrator_card` | `CLOSED_CHECKPOINT`: Gymmy key/success/card→club/daily aggregation доказаны. |
| 26 | `title_sheet` | `CLOSED_CHECKPOINT`: внутренние source branches закрыты; Excel остаётся вне PostgreSQL. |
| 27 | `marketing_funnel` | `CLOSED_CHECKPOINT`: task code, current DAX traffic и bounded rebuild доказаны. |
| 28 | `client_base` | `CLOSED_CHECKPOINT`: boundary 00:00 и club/network dedup сохранены; daily dependency доказана WA-V06C. |
| 29 | `dpfu_revenue` | `CLOSED_CHECKPOINT`; четыре shared products уже прошли собственный admission. |
| 30 | `membership_board` | `CLOSED_CHECKPOINT`: receipt reuse, current keys/state/sign доказаны; ненаблюдаемая ПКО-ветка сохранена по BR-018. |
| 31 | `revenue_group_summary` | `CLOSED_CHECKPOINT`: class-B accounting review завершён; внешние Excel ветви не переносятся. |

## 38 целевых продуктов

| Категория текущего состояния | Объекты | Вывод review |
|---|---|---|
| Собственная физическая приёмка пройдена (7) | `mart.ip_training_daily`, `mart.ancillary_revenue_movement`, `mart.dpfu_plan_assignment`, `mart.prebooking_state_event`, `mart.group_lesson`, `mart.lesson_room_slot_5m`, `mart.ip_revenue_daily` | Их admission закрыт; повторная загрузка возможна только при новом триггере. |
| Не созданы; source review закрыт или правило сохранено (31) | `mart.client_base_snapshot`, `mart.client_base_daily`, `mart.client_base_retention`, `mart.visit_client_day`, `mart.club_day_metrics`, `mart.club_attendance_hourly`, `mart.employee_activity_interval`, `mart.employee_presence_day`, `mart.crm_interaction`, `mart.v_sales_interaction`, `mart.v_feedback_interaction`, `mart.v_guest_tour`, `mart.new_first_visit`, `mart.guest_visit_conversion`, `mart.fitness_leads_funnel_task`, `mart.children_package_sale`, `mart.promo_application`, `mart.unconfirmed_service_debt_movement`, `mart.administrator_card_gymmy_daily`, `mart.v_administrator_bookings_daily`, `mart.v_reception_revenue`, `mart.revenue_group_summary_daily`, `mart.membership_receipt_movement`, `mart.membership_contract_kpi_unit`, `mart.preparation_renewal_checkpoint`, `mart.contract_usage`, `mart.fitness_funnel_client_start`, `mart.fitness_funnel_client_outcome`, `mart.renewal_management_contract`, `mart.newcomer_engagement_milestone`, `mart.newcomer_engagement_second_month` | Их создание всё ещё запрещено текущим gate. После отдельного разрешения каждый получает собственный product-admission: DDL, точная загрузка, ключи, reconciliation, rerun и SLA. |

Ни один из 38 объектов не нуждается в новом отдельном правиле только потому,
что он ещё не создан. Для всех найденных legacy-аномалий действуют либо
подтверждённые правила, либо BR-018; внешние Excel и Power Query остаются за
границей PostgreSQL.

## Итог для решения о gate

Не найдено ни одного незакрытого source-side вопроса, который можно безопасно
решить дополнительным автоматическим действием в текущем read-only режиме.
Существуют только два следующих типа проверок: product-admission после
создания объекта и согласованные BR-018 артефакты, которые не меняют первый
релиз.

Следующее отдельное полномочие — пользовательское подтверждение одного
заранее названного Stage-3 product-admission пакета. Режим планирования не
открывает runnable package selection и не разрешает DDL/DML.
