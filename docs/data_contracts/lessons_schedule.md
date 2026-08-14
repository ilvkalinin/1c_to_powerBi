# Data contract: «Уроки и расписание»

Статус: `IMPLEMENTED / initial BR-003 load VALIDATED — S3-LS-001—003`.

## Основной объект

| Параметр | Значение |
|---|---|
| Объект | `mart.lesson_room_slot_5m` |
| Таблица Power BI | `Занятость залов` |
| Grain | занятие из одной ветви × пятиминутный слот |
| Ключ | `(source_kind, source_lesson_id, slot_start_at)` |
| Обновление | ежедневно, bounded rebuild BR-003 |
| Режим | Import |

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `source_kind` | `Вид занятия` | text | нет | срез | не мера | нет |
| `source_lesson_id` | `ID занятия` | text | нет | ключ | не мера | да |
| `created_at` | `Дата создания` | timestamp | нет | detail | не мера | нет |
| `lesson_start_at`, `lesson_end_at` | `Начало`, `Окончание` | timestamp | нет | detail | не мера | нет |
| `slot_start_at` | `Начало слота` | timestamp | нет | часть ключа | не мера | нет |
| `club_id`, `room_id`, `employee_id`, `service_id`, `activity_id`, `training_format_id` | скрытые `ID ...` | text | по mapping | FK | не мера | да |
| `payment_class_current` | `Класс оплаты` | text | да | срез | не мера | нет |
| `schedule_entry_timeliness` | `Своевременность внесения` | text | нет | срез | не мера | нет |
| `is_cancelled_current` | `Отменено` | boolean | да | фильтр | не мера | да |
| `occupied_slot_count` | `Занятый слот` | smallint | нет | показатель | аддитивна | да |

`mart.group_lesson` и `mart.prebooking_state_event` остаются отдельными
фактами для вместимости, записей и пришедших; эти показатели не повторяются
на слотах. Связи общих измерений — `1:*`, single direction. PostgreSQL
разворачивает интервалы в слоты; DAX считает часы, структуру занятости,
рейтинги и доли.

Приёмка: один document before slot expansion, точное число слотов, корректные
отмены/классы, отсутствие дублей, контрольная занятость и SLA. BR-021 требует
расширить положительный неполный интервал до полного последнего 5-минутного
слота; исходная граница занятия остаётся в `lesson_end_at`. Неположительные
интервалы не создают слот и контролируются отдельно.
