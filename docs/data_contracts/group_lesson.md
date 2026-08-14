# Data contract: «Групповые занятия»

Статус: `IMPLEMENTED / initial BR-003 load VALIDATED — S3-GL-001—003`.

| Параметр | Значение |
|---|---|
| Объект | `mart.group_lesson` |
| Power BI table | `Групповые занятия` |
| Grain | одно непомеченное групповое занятие |
| Key | `group_lesson_id` |
| Refresh | daily full BR-003 rebuild after `mart.prebooking_state_event` |
| Power BI | Import; calendar/club/activity/employee/service are `1:*`, single direction |

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `group_lesson_id` | technical key | text | нет | key | не мера | да |
| `lesson_created_at` | дата регистрации | timestamp | нет | detail | не мера | нет |
| `lesson_start_at`, `lesson_end_at` | начало / окончание | timestamp | нет | calendar/detail | не мера | нет |
| `club_id`, `activity_id`, `employee_id`, `service_id` | скрытые ID | text | activity да | FKs | не мера | да |
| `capacity` | вместимость | integer | да | metric | аддитивна только с lesson grain | нет |
| `is_free_program` | бесплатная программа | boolean | нет | payment slice | не мера | нет |
| `active_booking_count` | активные записи | bigint | нет | metric | аддитивна | нет |
| `arrived_count` | пришедшие | bigint | нет | metric | аддитивна | нет |
| `free_program_arrived_count` | пришедшие бесплатной программы | integer | нет | audit/detail | аддитивна | да |

`capacity` is never summed across an event-level relation. Relationships to
`mart.prebooking_state_event` are not created; shared dimensions filter both
facts independently. `lesson_start_at` is the calendar field and BR-003
refresh bound; `lesson_created_at` stays a detail date only.
