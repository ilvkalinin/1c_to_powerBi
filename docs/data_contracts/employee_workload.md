# Data contract: «Загрузка сотрудников»

Статус: `employee_activity_interval IMPLEMENTED / presence facts DESIGNED, physical implementation deferred`.

## Новые объекты

| Объект | Таблица Power BI | Grain / ключ |
|---|---|---|
| `mart.employee_activity_interval` | `Активность сотрудников` | урок ПЗ/ГЗ, дежурство или coupon event × сотрудник × клуб × интервал |
| `mart.employee_presence_day` | `Присутствие сотрудников` | `(employee_id, presence_date, club_id)`; only exact-one employee domain by BR-043 |
| `mart.employee_presence_unattributed_day` | `Присутствие без сотрудника` | `(presence_date, club_id, attribution_status)`; `NO_EMPLOYEE`/`MULTIPLE_EMPLOYEES`, no `employee_id`, by BR-043 |

### `mart.employee_activity_interval`

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `activity_event_key` | `Ключ события` | text | нет | ключ | не мера | да |
| `activity_date` | `Дата активности` | date | нет | FK даты | не мера; coupon = visit day | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `employee_id` | `ID сотрудника` | text | нет | FK сотрудника | не мера | да |
| `activity_id` | `ID вида деятельности` | text | да | FK | не мера | да |
| `service_id` | `ID услуги` | text | да | FK | не мера | да |
| `room_id` | `ID помещения` | text | да | FK | не мера | да |
| `activity_kind` | `Вид активности` | text | нет | срез | не мера | нет |
| `start_at` | `Начало` | timestamp | нет | detail | не мера | нет |
| `end_at` | `Окончание` | timestamp | нет | detail | не мера | нет |
| `duration_minutes` | `Минуты активности` | numeric | нет | показатель | coupon formula; clean duty is nonnegative by BR-040 | нет |
| `payment_kind` | `Вид оплаты` | text | нет | срез | не мера | нет |

### `mart.employee_presence_day`

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `presence_date` | `Дата присутствия` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `employee_id` | `ID сотрудника` | text | нет | FK сотрудника | не мера | да |
| `presence_minutes` | `Минуты в клубе` | numeric | нет | показатель | аддитивна | нет |

### `mart.employee_presence_unattributed_day`

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `presence_date` | `Дата присутствия` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `attribution_status` | `Статус атрибуции` | text | нет | срез | не мера | нет |
| `presence_minutes` | `Минуты без сотрудника` | numeric | нет | показатель | аддитивна | нет |

`attribution_status` ограничен `NO_EMPLOYEE` и `MULTIPLE_EMPLOYEES`; связи с
employee dimension нет. Power BI остаётся `DESIGNED` по BR-036, без switch.

Модель также REUSE факты ДПФУ, план ДПФУ и ИП. Общие дата, клуб, сотрудник,
вид деятельности, услуга и помещение фильтруют применимые факты `1:*`, single
direction. Пороги остаются внешним Power BI-фактом без прямой связи к фактам.

Для первого релиза PostgreSQL воспроизводит current-M интервалы, `VT4352`
кратность и raw-сумму coupon/duty intersections; он не заменяет её union-логикой
без отдельного решения. DAX считает часы, доли, `% загрузки`, факт-план и
эффективность. Приёмка требует уникальность технически определённых событий,
reconciliation часов/выручки/плана, rerun и SLA. `employee_presence_day`
остаётся отдельной витриной и не получает неоднозначную СКУД-атрибуцию.

`employee_presence_day` не получает ни fallback employee, ни hidden
deduplication. BR-043 сохраняет 30,139 проблемных current-M-qualified visits
в отдельном non-personal product, поэтому split — явная целевая методика, а не
current-result reproduction. Evidence: [`EPD decision`](../reports/employee_presence_day_attribution_decision_2026-08-28.md).

`activity_event_key` подтверждён для ПЗ (`PZ + Document329 + VT4352 line`),
ГЗ (`GZ + Document279`), дежурства (hash точной M-группы) и coupon event
(hash current-M distinct group). В 149 coupon groups различалось только время
визита: день, минуты, договор и dimension IDs совпадают, поэтому ключ
детерминирован. Evidence: [`Stage 2 validation`](../reports/employee_activity_interval_stage2_validation_2026-08-27.md) и
[`follow-up`](../reports/employee_activity_interval_followup_validation_2026-08-27.md).
