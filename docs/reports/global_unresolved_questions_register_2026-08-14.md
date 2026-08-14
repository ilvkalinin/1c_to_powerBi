# Единый реестр нерешённых вопросов — 2026-08-14

Статус: `GLOBAL_STAGE_GATE_BLOCKED`.

## Назначение и правило закрытия

Это не план запуска и не разрешение на проверку. Реестр фиксирует полный
текущий набор критичных вопросов по 31 договорному отчёту, шести строкам вне
договорного scope и всем 38 проектируемым/реализованным объектам `mart` из
каталога. Пока у строки есть `OPEN`, `DECISION_REQUIRED` или
`VALIDATION_REQUIRED`, глобальный gate остаётся `BLOCKED`: нельзя открывать
новый пакет, выполнять новую Stage-2 проверку, переходить в Stage 3 или
создавать объект.

Закрытие строки требует одного из двух доказательных результатов:

1. read-only evidence подтверждает текущую SQL/M/DAX-логику и это записано в
   source validation; либо
2. пользователь принимает явное решение по BR-018, если current result нельзя
   воспроизвести без выбора ключа, grain, join, атрибуции, окна или формулы.

`IMPLEMENTED` у объекта означает только, что прошёл его собственный admission;
это не закрывает вопросы отчётов-потребителей. Внешние Excel и Power Query не
являются задачей PostgreSQL и не исследуются по постоянному ограничению
проекта.

## Реестр договорных отчётов

| № | Отчёт | Состояние вопроса | Что именно не закрыто | Затронутые продукты / evidence |
|---:|---|---|---|---|
| 1 | KPI Фитнеса | `OPEN` | Общая выручка, ИП и план уже загружены, но остаются client-base/регулярность и полный report-level reconciliation без смены DAX. | `mart.client_base_daily`; ADR-0012; SV-054—061 |
| 2 | Вовлечение новичков | `VALIDATION_REQUIRED` | Кардинальность contract join, интервалы заморозок и сохранение current-state строк. | `mart.newcomer_engagement_milestone`; SV-075/092; ADR-0008 |
| 3 | Вовлечение новичков, второй месяц | `DECISION_REQUIRED` | Child/СПТ связи не one-to-one; нельзя скрыто дедуплицировать legacy `RANK()` ties. | `mart.newcomer_engagement_second_month`; SV-076; ADR-0009 |
| 4 | Подготовка к продлению | `VALIDATION_REQUIRED` | Состояния `Active`/удаление/сторно, обратные интервалы и дубликаты freeze/visit join. | `mart.preparation_renewal_checkpoint`; SV-077; ADR-0013 |
| 5 | Воронка лиды фитнес | `VALIDATION_REQUIRED` | Уникальность задания и наблюдаемая cardinality task→service/contract должны сохраниться в физическом факте. | `mart.fitness_leads_funnel_task`; SV-078; ADR-0011 |
| 6 | Загрузка сотрудников | `DECISION_REQUIRED` | Ключ активности, пересечения дежурств/купонов, связь СКУД→сотрудник и единственная кадровая запись при пересекающихся интервалах. | `mart.employee_activity_interval`, `mart.employee_presence_day`; SV-074; ADR-0014 |
| 7 | Контроль предварительной записи | `DECISION_REQUIRED` | Legacy multiplicity `VT4352`, orphan enum и расходящиеся document/registry service/club нельзя нормализовать без BR-018. | `mart.prebooking_state_event`, `mart.group_lesson`; SV-072; ADR-0015 |
| 8 | Отчёт по ИП | `VALIDATION_REQUIRED` | Факт тренировок создан, но branch multiplicity и report-level current `COUNT(Контрагент)` должны быть сверены без замены ключа тренировки. | `mart.ip_training_daily`; SV-058/068; ADR-0025 |
| 9 | Посещения Физкульт | `VALIDATION_REQUIRED` | Полный scope, защита ключа и late changes; категории посещений остаются пересекающимися по current rule. | `mart.visit_client_day`; SV-070; ADR-0003 |
| 10 | Уроки и расписание | `DECISION_REQUIRED` | Interval/state ветви и orphan dimensions должны воспроизводить legacy; room slots не подтверждают все агрегаты расписания. | `mart.group_lesson`, `mart.lesson_room_slot_5m`; SV-073; ADR-0015 |
| 11 | Фитнес воронка | `VALIDATION_REQUIRED` | Когорта client×start подтверждена частично; ключи outcome и отсутствие contract attribution остаются к проверке. | `mart.fitness_funnel_client_start`, `mart.fitness_funnel_client_outcome`; SV-079; ADR-0026 |
| 12 | Загрузка ОП | `VALIDATION_REQUIRED` | Interaction/phone grain, кадровые даты и full-population/state controls CRM. | `mart.crm_interaction`, `mart.v_sales_interaction`; SV-084; ADR-0016 |
| 13 | Отчёт по поступлениям | `DECISION_REQUIRED` | Физический ключ, states/sign и recurring KPI-unit; нельзя заменять `analytics_sequence` и predecessor `MIN(ID)`. | `mart.membership_receipt_movement`, `mart.membership_contract_kpi_unit`; SV-083; ADR-0017 |
| 14 | Отчёт по промокодам | `DECISION_REQUIRED` | Join размножает движения; legacy `MAX/SUM/Table.Distinct` и DAX fallback нельзя заменить дедупликацией. | `mart.promo_application`; SV-090/091; ADR-0018 |
| 15 | Продажа детских пакетов | `VALIDATION_REQUIRED` | Line-to-line price/product, знак возврата и source states не подтверждены. | `mart.children_package_sale`; SV-085; ADR-0019 |
| 16 | Управление продлением | `VALIDATION_REQUIRED` | Требуются полные cardinality controls для same-client/first-start, статусов и CRM; текущая эвристика не становится прямой ссылкой. | `mart.renewal_management_contract`; SV-081; ADR-0007 |
| 17 | Отчёт по %Renew | `VALIDATION_REQUIRED` | Contract key, current window/`COUNT(*)`, `Fld693` и финализация закрытого месяца. | `mart.contract_usage`; SV-082; ADR-0006 |
| 18 | Выручка рецепции | `VALIDATION_REQUIRED` | Атрибуция продавца и точный report view поверх общего факта; `_document294` не добавляется без решения об изменении атрибуции. | `mart.v_reception_revenue_daily`; SV-050—053; ADR-0005 |
| 19 | Записи администраторов | `VALIDATION_REQUIRED` | Booking→movement cardinality/sum и кадровая атрибуция: уже найдено 99 документов с одним match и один с четырьмя. | `mart.v_administrator_bookings_daily`; SV-086; ADR-0004 |
| 20 | Новички и гостевые визиты | `DECISION_REQUIRED` | Guest candidate key дублируется; status, first-rank и 0–44-day outcome нельзя выбрать эвристикой. | `mart.v_guest_tour`, `mart.new_first_visit`, `mart.guest_visit_conversion`; SV-087; ADR-0020 |
| 21 | Отчёт по обращениям | `VALIDATION_REQUIRED` | HTML/follow-up, feedback cardinality и знаменатель посещений; сохраняется current phone multiplicity. | `mart.crm_interaction`, `mart.v_feedback_interaction`; SV-088; ADR-0016 |
| 22 | Посещаемость клиентов с долгами | `VALIDATION_REQUIRED` | Технический key, source states, document branches, as-of границы, RecordKind/sign и cardinality сотрудника. | `mart.unconfirmed_service_debt_movement`, `mart.visit_client_day`; SV-089; ADR-0021 |
| 23 | Посещения Пушкинский | `VALIDATION_REQUIRED` | Snapshot, категории и исключение ДРЦ должны быть подтверждены на полном scope. | `mart.visit_client_day`, `mart.club_day_metrics`; SV-071; ADR-0003 |
| 24 | Работа с посещаемостью | `VALIDATION_REQUIRED` | Не сформирован daily client-base denominator; годовой source query превысил timeout, SLA не измерен; шкафчики остаются вне PostgreSQL. | `mart.club_attendance_hourly`, `mart.client_base_daily`; SV-065/067; ADR-0022 |
| 25 | Карта администратора | `VALIDATION_REQUIRED` | Gymmy key, successful-event, card→club и daily count; сохраняются 12 карт, два направления и `SUM(usage_count)`. | `mart.administrator_card_gymmy_daily`; SV-002; ADR-0023 |
| 26 | Титульный лист | `OPEN` | Внутренние source controls пройдены, но свод требует готовых shared dependencies; внешние Excel-ветви остаются в Power BI. | `mart.revenue_group_summary_daily`, `mart.client_base_daily`, `mart.club_attendance_hourly`; SV-062—064; ADR-0024 |
| 27 | Маркетинговая воронка | `VALIDATION_REQUIRED` | Physical code/join/state controls для task×contract; BR-020 требует считать каждую qualified связь. | `mart.fitness_leads_funnel_task`; SV-080; ADR-0011 |
| 28 | Клиентская база | `DECISION_REQUIRED` | Package/visit/state controls, control values и физическое представление `NULL/Не определено`; retention имеет отдельный grain. | `mart.client_base_snapshot`, `mart.client_base_retention`, `mart.client_base_daily`; SV-069; ADR-0002 |
| 29 | Выручка ДПФУ | `OPEN` | Четыре shared products загружены, но report-specific model/reconciliation целиком ещё не закрыты; не создавать вторые копии движений. | `mart.ancillary_revenue_movement`, `mart.dpfu_plan_assignment`, `mart.ip_training_daily`, `mart.ip_revenue_daily`; ADR-0005/0012 |
| 30 | Членство для правления | `DECISION_REQUIRED` | Physical key/state, board reconciliation и non-additive KPI controls; BR-015/016 и recurring unit не заменяются. | `mart.membership_receipt_movement`, `mart.membership_contract_kpi_unit`; SV-083; ADR-0017 |
| 31 | Свод выручка ГК | `VALIDATION_REQUIRED` | Ключ дневной статьи, internal branches и граница с внешними Excel-ветвями без их переноса. | `mart.revenue_group_summary_daily`; SV-035—050/066; ADR-0010 |

## Шесть строк вне договорного scope

| Отчёт | Состояние | Что требуется, прежде чем он станет частью global review |
|---|---|---|
| Карты будущего периода | `DECISION_REQUIRED` | Явно включить в договорный scope и предоставить подтверждённые материалы. |
| Edna | `DECISION_REQUIRED` | То же; это отдельный коммуникационный домен. |
| Несчастные случаи | `DECISION_REQUIRED` | То же; это отдельный инцидентный домен. |
| Пульс клуба 2026 | `DECISION_REQUIRED` | То же; включает несколько доменов и внешние данные. |
| Группа VK Физкульт (Анализ постов) | `DECISION_REQUIRED` | То же; внешний маркетинговый источник. |
| Директ | `DECISION_REQUIRED` | То же; внешний рекламный источник. |

## Реестр объектов `mart`

| Объект | Состояние | Критичный незакрытый вопрос или подтверждённая граница |
|---|---|---|
| `mart.client_base_snapshot` | `VALIDATION_REQUIRED` | Полный source scope, states и control values. |
| `mart.client_base_daily` | `VALIDATION_REQUIRED` | Уникальный daily denominator и полное календарное покрытие. |
| `mart.client_base_retention` | `VALIDATION_REQUIRED` | Baseline cohort и retention intersection имеют отдельный grain. |
| `mart.visit_client_day` | `VALIDATION_REQUIRED` | Key protection, full scope и late changes. |
| `mart.club_day_metrics` | `VALIDATION_REQUIRED` | Полное подтверждение зависимых visit/day source sets. |
| `mart.club_attendance_hourly` | `VALIDATION_REQUIRED` | Daily client-base dependency и измеренный historical SLA. |
| `mart.ip_training_daily` | `IMPLEMENTED` | Собственный admission закрыт; открыты только вопросы отчётов-потребителей. |
| `mart.employee_activity_interval` | `DECISION_REQUIRED` | Event key, states, coupon/duty overlap и кадровая атрибуция. |
| `mart.employee_presence_day` | `VALIDATION_REQUIRED` | Однозначная СКУД→сотрудник связь и отсутствие размножения часов. |
| `mart.crm_interaction` | `VALIDATION_REQUIRED` | States, full population и идентичность interaction key. |
| `mart.v_sales_interaction` | `VALIDATION_REQUIRED` | Phone-row semantics и кадровый отбор. |
| `mart.v_feedback_interaction` | `VALIDATION_REQUIRED` | HTML/follow-up/cardinality и visit denominator. |
| `mart.v_guest_tour` | `VALIDATION_REQUIRED` | Filter/state и 44-day outcome controls. |
| `mart.new_first_visit` | `VALIDATION_REQUIRED` | First-rank tie-break и PII-detail grain. |
| `mart.guest_visit_conversion` | `DECISION_REQUIRED` | Дубли candidate key и правило статуса/конверсии. |
| `mart.fitness_leads_funnel_task` | `VALIDATION_REQUIRED` | Task key и physical task×contract controls. |
| `mart.children_package_sale` | `VALIDATION_REQUIRED` | Check-line price/product, возвраты и states. |
| `mart.promo_application` | `DECISION_REQUIRED` | Устранение join-multiplicity без изменения legacy результата. |
| `mart.ancillary_revenue_movement` | `IMPLEMENTED` | Собственный admission закрыт; повторная загрузка запрещена без нового триггера. |
| `mart.dpfu_plan_assignment` | `IMPLEMENTED` | Собственный admission закрыт; плановые потребители ещё требуют report-level controls. |
| `mart.prebooking_state_event` | `IMPLEMENTED` | Собственный admission закрыт; legacy multiplicity остаётся границей потребителей. |
| `mart.unconfirmed_service_debt_movement` | `VALIDATION_REQUIRED` | Key, states, as-of/document branches и sign. |
| `mart.group_lesson` | `IMPLEMENTED` | Собственный admission закрыт; не заменяет правила полного расписания. |
| `mart.lesson_room_slot_5m` | `IMPLEMENTED` | Собственный admission закрыт; BR-021 и два nonpositive source controls зафиксированы. |
| `mart.administrator_card_gymmy_daily` | `VALIDATION_REQUIRED` | Key, success, card→club и count. |
| `mart.v_administrator_bookings_daily` | `VALIDATION_REQUIRED` | Booking→movement cardinality/sum и кадровая атрибуция. |
| `mart.v_reception_revenue_daily` | `VALIDATION_REQUIRED` | Seller attribution и report-view grain. |
| `mart.revenue_group_summary_daily` | `VALIDATION_REQUIRED` | Daily article key и validated internal branches. |
| `mart.membership_receipt_movement` | `DECISION_REQUIRED` | Physical key, states/sign и legacy sequence. |
| `mart.membership_contract_kpi_unit` | `VALIDATION_REQUIRED` | Recurring key и KPI-unit grain. |
| `mart.preparation_renewal_checkpoint` | `VALIDATION_REQUIRED` | Freeze/visit joins, states и interval integrity. |
| `mart.ip_revenue_daily` | `IMPLEMENTED` | Собственный admission закрыт; payment-date grain не заменяет другие факты. |
| `mart.contract_usage` | `VALIDATION_REQUIRED` | Contract key/window, `COUNT(*)`, `Fld693` и closed-month finalization. |
| `mart.fitness_funnel_client_start` | `VALIDATION_REQUIRED` | Cohort client-start key и dedupe. |
| `mart.fitness_funnel_client_outcome` | `VALIDATION_REQUIRED` | Source key и attribution absence. |
| `mart.renewal_management_contract` | `VALIDATION_REQUIRED` | Same-client/first-start, state и CRM cardinality. |
| `mart.newcomer_engagement_milestone` | `VALIDATION_REQUIRED` | Contract/freeze join and state preservation. |
| `mart.newcomer_engagement_second_month` | `DECISION_REQUIRED` | Child/СПТ cardinality and legacy rank ties. |

## Управление gate

Файл `.agents/project_stage_gate.tsv` остаётся `BLOCKED`. Его нельзя менять по
одной закрытой строке или по факту появления одной витрины. Сначала реестр
должен получить evidence/решение для всех строк, затем проводится отдельный
review полноты и только после явного решения пользователя gate может стать
`OPEN`.

Порядок будущего полного review, не являющийся разрешением на его запуск,
зафиксирован в [плане закрытия](global_question_closure_plan_2026-08-14.md).

## Источники реестра

- `docs/reports/contract_scope.md` — 31 договорный отчёт и шесть строк вне scope;
- `docs/reports/stage_2_transition_readiness_2026-08-13.md` — условия каждого
  перехода и классы A/B/C;
- `docs/catalogs/data_products.md` — 38 проектируемых и реализованных объектов;
- соответствующие ADR, mapping, data contract и query review, указанные в
  строках выше.
