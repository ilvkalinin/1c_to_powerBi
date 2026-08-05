# Data contract: «Загрузка сотрудников»

Статус: `DESIGNED COMPOSITE MODEL / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

## Новые объекты

| Объект | Таблица Power BI | Grain / ключ |
|---|---|---|
| `mart.employee_activity_interval` | `Активность сотрудников` | одно событие × сотрудник × клуб × интервал × вид активности; key pending |
| `mart.employee_presence_day` | `Присутствие сотрудников` | `(employee_id, presence_date, club_id)` |

### `mart.employee_activity_interval`

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `activity_event_key` | `Ключ события` | text | нет | ключ | не мера | да |
| `activity_date` | `Дата активности` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `employee_id` | `ID сотрудника` | text | нет | FK сотрудника | не мера | да |
| `activity_id` | `ID вида деятельности` | text | да | FK | не мера | да |
| `service_id` | `ID услуги` | text | да | FK | не мера | да |
| `room_id` | `ID помещения` | text | да | FK | не мера | да |
| `activity_kind` | `Вид активности` | text | нет | срез | не мера | нет |
| `start_at` | `Начало` | timestamp | нет | detail | не мера | нет |
| `end_at` | `Окончание` | timestamp | нет | detail | не мера | нет |
| `duration_minutes` | `Минуты активности` | numeric | нет | показатель | аддитивна после защиты overlap | нет |
| `payment_kind` | `Вид оплаты` | text | нет | срез | не мера | нет |

### `mart.employee_presence_day`

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `presence_date` | `Дата присутствия` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `employee_id` | `ID сотрудника` | text | нет | FK сотрудника | не мера | да |
| `presence_minutes` | `Минуты в клубе` | numeric | нет | показатель | аддитивна | нет |

Модель также REUSE факты ДПФУ, план ДПФУ и ИП. Общие дата, клуб, сотрудник,
вид деятельности, услуга и помещение фильтруют применимые факты `1:*`, single
direction. Пороги остаются внешним Power BI-фактом без прямой связи к фактам.

PostgreSQL нормализует интервалы и overlap купонов/дежурств. DAX считает часы,
доли, `% загрузки`, факт-план и эффективность. Приёмка: уникальность событий,
неотрицательные чистые дежурства, однозначная СКУД-связь, reconciliation часов,
выручки и плана, rerun и SLA.

