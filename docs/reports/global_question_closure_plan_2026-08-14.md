# План закрытия глобального реестра вопросов — 2026-08-14

Статус: `PLAN_ONLY / GLOBAL_STAGE_GATE_BLOCKED`.

Этот документ не открывает пакет, не разрешает Stage 2, Stage 3, доступ к
источнику, DDL или DML. Он описывает единственный допустимый путь от реестра
нерешённых вопросов к возможному будущему review глобального gate.

Основание: [единый реестр](global_unresolved_questions_register_2026-08-14.md)
и `.agents/project_stage_gate.tsv`.

## Что считается закрытием

Для каждой строки реестра должен быть один из результатов:

| Статус результата | Доказательство |
|---|---|
| `VALIDATED` | Read-only control с сохранённым SQL/result, явно подтверждающий текущую логику. |
| `VALIDATION_FAILED` | Зафиксированное расхождение и отдельное решение BR-018, что именно сохраняется или меняется. |
| `CONFIRMED` | Явное пользовательское решение для grain, ключа, join, атрибуции, окна или формулы. |
| `NOT_APPLICABLE` | Доказанная граница: вопрос относится к внешнему Excel/Power Query либо к отчёту вне договорного scope. |

Статус `PARTIALLY VALIDATED`, наличие одной готовой витрины или закрытие
одного отчёта не считаются снятием global gate.

## Предлагаемая логика будущего полного review

```text
реестр вопросов
  → доказательства общих источников и ключей
  → доказательства report-specific join/state/grain
  → решения только по найденным развилкам BR-018
  → повторный audit всех 37 строк и 38 объектов
  → явное решение пользователя о снятии global gate
```

До отдельного разрешения пользователя ни один из этих шагов не исполняется.

## Порядок зависимостей

| Очередь будущего review | Общий вопрос | Почему раньше зависимых отчётов | Зависимые отчёты / продукты |
|---:|---|---|---|
| 1 | Контракты, client base, visits и states | Это ключи для retention, посещений, долгов, renew и загрузки. | 2, 3, 4, 9, 16, 17, 22, 23, 24, 28; `client_base_*`, `visit_client_day` |
| 2 | Занятия, предзапись, интервалы и кадровая атрибуция | Определяет строки расписания, ИП, дежурств и загрузки сотрудников. | 6, 7, 8, 10, 11; `employee_*`, `prebooking_state_event`, `group_lesson`, `lesson_room_slot_5m` |
| 3 | CRM interaction/task и связи с контрактами | Нужен один доказанный core для ОП, обращений, гостей и обеих воронок. | 5, 12, 20, 21, 27; `crm_interaction`, `fitness_leads_funnel_task`, guest views |
| 4 | Membership/receipts, промо и детские продажи | Нужны movement key, знак, states и line-to-line cardinality. | 13, 14, 15, 30; `membership_*`, `promo_application`, `children_package_sale` |
| 5 | Выручка и атрибуция отчётных views | Общие факты уже не копируются; остаются потребительские joins и daily grains. | 1, 18, 19, 26, 29, 31; `ancillary_revenue_movement`, `dpfu_plan_assignment`, revenue views |
| 6 | Производительность, SLA, безопасность и контроль Power BI | Это финальная проверка того, что подтверждённая семантика пригодна для обновления. | 1, 12, 21, 24, 25, 26, 29, 30, 31 |

## Матрица закрытия по договорным отчётам

| № | Отчёт | Что должно быть доказано или решено | Зависит от очереди |
|---:|---|---|---:|
| 1 | KPI Фитнеса | Полная сверка shared facts с текущими KPI/DAX и daily client-base/regularity. | 1, 5, 6 |
| 2 | Вовлечение новичков | Contract/freeze/visit cardinality и current-state сохранение. | 1 |
| 3 | Вовлечение новичков, второй месяц | Child/СПТ multiplicity; BR-018 для legacy rank ties при расхождении. | 1, 2 |
| 4 | Подготовка к продлению | Freeze/visit states, обратные интервалы и дубликаты join. | 1 |
| 5 | Воронка лиды фитнес | Task key и bounded task→service/contract cardinality. | 3 |
| 6 | Загрузка сотрудников | Activity/presence keys, duty/coupon overlap, СКУД→сотрудник, кадровые интервалы. | 1, 2 |
| 7 | Контроль предварительной записи | `VT4352` multiplicity, enum/document/registry branch и service/club divergence. | 2 |
| 8 | Отчёт по ИП | Training key/branch multiplicity и current count reconciliation. | 2, 5 |
| 9 | Посещения Физкульт | Full visit scope, key protection, late changes и current categories. | 1 |
| 10 | Уроки и расписание | Legacy state/interval branches, orphan dimensions и lesson aggregates. | 2 |
| 11 | Фитнес воронка | Client-start cohort, outcome keys и отсутствие contract attribution. | 1, 2, 3 |
| 12 | Загрузка ОП | Interaction/phone grain, role dates, states и full population. | 3, 6 |
| 13 | Отчёт по поступлениям | Movement key/state/sign и recurring KPI-unit без изменения legacy sequence. | 4 |
| 14 | Отчёт по промокодам | Join multiplicity; BR-018 для legacy aggregation/fallback. | 4 |
| 15 | Продажа детских пакетов | Price/product line link, return sign и source states. | 4 |
| 16 | Управление продлением | Same-client/first-start, states и CRM cardinality. | 1, 3 |
| 17 | Отчёт по %Renew | Contract key/window, `COUNT(*)`, `Fld693`, closed-month finalization. | 1 |
| 18 | Выручка рецепции | Seller attribution и view grain поверх общего факта. | 5 |
| 19 | Записи администраторов | Booking→movement count/sum и кадровая атрибуция. | 2, 5 |
| 20 | Новички и гостевые визиты | Guest key/status, first-rank и 0–44-day outcome. | 1, 3 |
| 21 | Отчёт по обращениям | HTML/follow-up, feedback cardinality и visit denominator. | 1, 3, 6 |
| 22 | Посещаемость клиентов с долгами | Debt key/states/branches/as-of/sign и employee join. | 1, 2 |
| 23 | Посещения Пушкинский | Snapshot/categories/ДРЦ exclusion на полном scope. | 1 |
| 24 | Работа с посещаемостью | Daily client-base denominator, historical SLA и сохранение границы Excel шкафчиков. | 1, 6 |
| 25 | Карта администратора | Gymmy key/success/card→club/daily count. | 6 |
| 26 | Титульный лист | Internal dependencies и отчётная граница с внешними Excel ветвями. | 1, 5, 6 |
| 27 | Маркетинговая воронка | Physical task×contract code/join/state controls по BR-020. | 3 |
| 28 | Клиентская база | Package/visit/state controls, control values, `NULL/Не определено`, retention grain. | 1 |
| 29 | Выручка ДПФУ | Report-level reconciliation четырёх shared facts без второй копии движений. | 5, 6 |
| 30 | Членство для правления | Board reconciliation, non-additivity, key/state и recurring unit. | 4, 6 |
| 31 | Свод выручка ГК | Daily article key, internal branches и граница Excel. | 4, 5, 6 |

## Граница по объектам

Полный перечень 38 объектов и их текущий блокер остаётся в реестре; этот план
не повторяет его строка-в-строку. Перед снятием gate audit обязан подтвердить:

1. у каждого объекта со статусом `IMPLEMENTED` нет незакрытого собственного
   admission-контроля;
2. у каждого проектируемого объекта есть `VALIDATED`, `CONFIRMED` или
   `NOT_APPLICABLE` по каждому критичному вопросу;
3. каждый report-specific view использует общий факт, а не создаёт повторную
   raw-копию;
4. все шесть строк вне договорного scope имеют явный `NOT_APPLICABLE` либо
   решение об их включении и отдельный подтверждённый scope.

## Будущее снятие gate

После полного evidence/decision audit может быть подготовлен только один
запрос пользователю: снять `GLOBAL_STAGE_GATE_BLOCKED` для заранее названного
пакета. До такого решения `scripts/check_package_selection.sh` обязан
отклонять каждый пакет; частичное открытие для одного отчёта этим планом не
предусмотрено.
