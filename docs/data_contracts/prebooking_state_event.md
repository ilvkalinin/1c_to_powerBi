# Data contract: «События предзаписи»

Статус: `STAGE_3 ADMISSION / DDL REVIEW PENDING`.

| Параметр | Значение |
|---|---|
| Объект | `mart.prebooking_state_event` |
| Таблица Power BI | `События предзаписи` |
| Grain | state-event × qualifying VT4352 line для ПЗ; state-event для ГЗ |
| Логический key | `(booking_kind, recorder_tref, recorder_id, source_line_no, legacy_settlement_line_no)` where nullable line compares literally |
| Refresh | daily full bounded rebuild BR-003 by `lesson_start_at` |
| Power BI | Import; common dimensions are `1:*`, single direction |

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `state_event_at` | `Дата и время события` | timestamp | нет | detail | не мера | нет |
| `booking_kind` | `Вид записи` | text | нет | branch | не мера | нет |
| `recorder_tref`, `recorder_id`, `source_line_no`, `legacy_settlement_line_no` | technical key | text/text/integer/integer | line да | uniqueness | не мера | да |
| `booking_document_id` | `ID записи` | text | нет | detail group | не мера | да |
| `lesson_start_at`, `lesson_end_at` | начало/окончание занятия | timestamp | нет | detail / calendar role | не мера | нет |
| `club_id`, `employee_id`, `service_id` | скрытые IDs | text | нет | common FKs | не мера | да |
| `activity_id` | скрытый ID вида деятельности | text | да | optional FK through current document-service left join | не мера | да |
| `client_key` | `Ключ клиента` | text | нет | detail key | не мера | да |
| `client_code`, `client_name` | код / клиент | text | да | PII detail | не мера | нет |
| `state_order` | порядок состояния | smallint | нет | branch filter | не мера | да |
| `event_category` | категория внесения | text | нет | slice | не мера | нет |
| `booking_delta` | изменение записей | smallint | нет | metric | аддитивна | нет |
| `cancelled_before_lesson`, `is_paid_booking` | признаки | boolean | cancelled да | slice | не мера | нет |

`booking_delta` already contains the preserved PZ multiplicity; DAX must sum
it, not count fact rows. Client code is never a key. Report-specific filters
by state/prepayment remain DAX filters and do not delete source rows.
