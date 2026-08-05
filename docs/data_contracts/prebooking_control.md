# Data contract: «Контроль предварительной записи»

Статус: `DESIGNED COMPOSITE MODEL / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

## Объекты

| Объект | Таблица Power BI | Grain |
|---|---|---|
| `mart.prebooking_state_event` | `События предзаписи` | одно событие состояния одной записи |
| `mart.dpfu_plan_assignment` | `План ДПФУ` | дата × клуб × направление × тренер × плановый клиент |
| `mart.group_lesson` | `Групповые занятия` | одно групповое занятие |

### События предзаписи

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `state_event_at` | `Дата и время события` | timestamp | нет | событие | не мера | нет |
| `booking_document_id` | `ID записи` | text | нет | ключ/группа | не мера | да |
| `booking_kind` | `Вид записи` | text | нет | срез | не мера | нет |
| `lesson_start_at`, `lesson_end_at` | `Начало занятия`, `Окончание занятия` | timestamp | нет | detail | не мера | нет |
| `club_id`, `activity_id`, `employee_id`, `service_id` | скрытые `ID ...` | text | по mapping | FK | не мера | да |
| `client_key` | `Ключ клиента` | text | нет | distinct | не мера | да |
| `client_code`, `client_name` | `Код клиента`, `Клиент` | text | да | PII-detail | не мера | нет |
| `state_order` | `Порядок состояния` | smallint | нет | классификация | не мера | да |
| `event_category` | `Категория внесения` | text | нет | срез | не мера | нет |
| `booking_delta` | `Изменение записей` | smallint | нет | показатель | аддитивна | нет |
| `cancelled_before_lesson` | `Отменено до занятия` | boolean | да | признак | не мера | нет |
| `is_paid_booking` | `Платная запись` | boolean | нет | фильтр | не мера | да |

### План и групповое занятие

План включает `plan_date date`, четыре ID `text`, `planned_client_key text`,
`planned_service_count smallint`, `planned_revenue numeric`. Групповое занятие
включает `group_lesson_id text`, границы `timestamp`, четыре ID `text`,
`capacity integer`, `active_booking_count bigint`, `arrived_count bigint`,
`free_program_arrived_count bigint`, `prepayment_type smallint`.

Общие календарь, клуб, деятельность, сотрудник и услуга фильтруют все факты
`1:*`, single direction. PII-detail доступна по BR-017. PostgreSQL рассчитывает
event category, delta и lesson aggregates; DAX — нетто-записи, доли,
рейтинги, план-факт и заполненность.

Приёмка: ключ/история состояния, взаимоисключимые document branches,
отсутствие размножения `VT4352`, уникальный план и lesson ID, корректные
enum/states, контрольные значения, rerun и SLA.

