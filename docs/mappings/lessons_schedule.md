# Source-to-target mapping: «Уроки и расписание»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0015 / TECHNICAL VALIDATION DEFERRED`.

Спроектированы `mart.lesson_room_slot_5m` и REUSE `mart.group_lesson`.
Production SQL не создаётся.

История следует `BR-003` (`CONFIRMED — решение пользователя 2026-07-30`).

## Целевые наборы и reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| `REUSE`: групповое занятие | Использовать логический набор «контроль предзаписи: групповое занятие» для `Document279`, вместимости, платных прибывших и бесплатных посетивших. | CONFIRMED reuse: [prebooking mapping](prebooking_control.md) |
| `EXTEND` существующих фактов | `visit_client_day`, `club_day_metrics`, факт ИП и события предзаписи имеют другой grain и не содержат интервал помещения. | REJECTED — CONFIRMED analysis |
| `NEW`: расписание и занятость | `mart.lesson_room_slot_5m`: занятие × 5-минутный слот из `Document279`/`Document329`. | DESIGNED — ADR-0015 |
| Общие измерения | Календарь, клуб, помещение, услуга, сотрудник и вид деятельности — REUSE источников/измерений. | CONFIRMED catalog; keys VALIDATION_PENDING |

Гранулярность нового логического набора: одно расписанное занятие из одной
документной ветви, развёрнутое на один 5-минутный интервал. Логический ключ
кандидат: `(source_kind, source_lesson_id, slot_start_at)`; физические ID и
уникальность требуют LS-V01.

## Колонки «расписание и занятость зала»

| Целевая колонка | Бизнес-описание | Источник | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `source_kind` | ветвь занятия | `Document279` / `Document329` | явные значения `group_lesson` / `prebooking` | `text` | нет | CONFIRMED current | LS-V01 |
| `source_lesson_id` | стабильная ссылка занятия | `Document279.ID` / `Document329.ID` | сохранить ID без текстового кодирования | UNKNOWN | нет | CONFIRMED current source | LS-V01 |
| `created_at` | момент внесения документа | `Date_Time` обеих таблиц | без округления | `timestamp` UNKNOWN | нет | CONFIRMED current | LS-V02 |
| `lesson_start_at` | начало занятия | `Document279.Fld3218` / `Document329.Fld4306` | по `source_kind` | `timestamp` UNKNOWN | нет | CONFIRMED current | LS-V01, LS-V03 |
| `lesson_end_at` | окончание занятия | `Document279.Fld3219` / `Document329.Fld4307` | по `source_kind`; интервал `[start,end)` | `timestamp` UNKNOWN | нет | CONFIRMED current | LS-V03 |
| `slot_start_at` | начало 5-минутного занятого интервала | `lesson_start_at`, `lesson_end_at` | серия с шагом 5 мин, начало включено, конец исключён | `timestamp` UNKNOWN | нет | CONFIRMED current calculation | LS-V03 |
| `club_id` | клуб занятия | `Fld3224` / `Fld4310` | стабильный ID, не описание | UNKNOWN | нет | CONFIRMED current | LS-V01 |
| `room_id` | помещение | `Fld3227` / `Fld4320` | стабильный ID | UNKNOWN | да | CONFIRMED current | LS-V01, LS-V04 |
| `employee_id` | ведущий сотрудник | `Fld3223` / `Fld4322` | стабильный ID | UNKNOWN | да | CONFIRMED current | LS-V01 |
| `service_id` | услуга | `Fld3226` / `Fld4316` | стабильный ID | UNKNOWN | да | CONFIRMED current | LS-V01 |
| `activity_id` | подразделение услуги | `Reference163.Fld1733` → `Reference70.ID` | stable ID | UNKNOWN | да | CONFIRMED current | LS-V01 |
| `training_format_id` | формат тренировки | `Reference163.Fld1803` → `Reference248.ID` | не заменять «Платный урок» текстом | UNKNOWN | да | CONFIRMED current source | LS-V04 |
| `payment_class_current` | клубное время / платное / резерв | `Reference163.Fld1778`, `Document279.Fld3228`, статус ПЗ | branch-specific current M; не считать универсальным правилом | `text` | да | CONFIRMED current calculation / semantics pending | LS-V05 |
| `schedule_entry_timeliness` | внесено до/после контрольного момента | `created_at`, `lesson_start_at`, `lesson_end_at` | `created_at > lesson_end_at` → `after`, ровно как в текущем M | `text` | нет | CONFIRMED — решение пользователя 2026-07-30 | LS-V06 |
| `is_cancelled_current` | отменённое занятие | `Document313`, статусы/флаги документов | current M различается по веткам; единый фильтр не подтверждён | `boolean` | UNKNOWN | VALIDATION_PENDING | LS-V02, LS-V05 |

## Переиспользуемые поля группового занятия

Для `Document279` использовать mapping `prebooking_control` без дублирования:
`group_lesson_id`, `lesson_start_at`, `lesson_end_at`, `club_id`,
`employee_id`, `service_id`, `activity_id`, `capacity`, `arrived_count`,
`free_program_arrived_count`, `prepayment_type`. Рейтинг и загрузка — меры
Power BI поверх подтверждённой вместимости и счётчиков.

## Источники

| Объект | Роль | Статус | Доказательство |
|---|---|---|---|
| `Document279` | групповое занятие, интервал, вместимость, зал | CONFIRMED source | M и metadata |
| `Document329` | предварительная запись, интервал, зал, статус | CONFIRMED source | M и metadata |
| `Document313` | отмена предварительной записи | CONFIRMED current source | M и metadata |
| `InfoRg7006`, `InfoRg8675` | прибывшие платных/бесплатных групповых занятий | CONFIRMED current source | M, [prebooking mapping](prebooking_control.md) |
| `Reference132/163/191/225/70/248` | измерения занятия | CONFIRMED current source | M и catalog |
| `InfoRg6015` | рабочий/выходной календарь текущей модели | CONFIRMED current source | M; business semantics pending |
| внешние `Волшебка_Спр`, `Волшебка__СпрПлощади`, `СПР_Помещения`, параметры УДВ, старая база | вместимость, типы, классификация, история | EXTERNAL / остаются в Power BI, не входят в PostgreSQL mapping | решение пользователя 2026-07-30 |
| `AccumRg7575`, `Document325`, `Reference59`, `Reference141X1` | знаменатель доли ГП | CONFIRMED current source | M; [work attendance mapping](work_attendance.md) |

## Подготовленные read-only проверки

Все проверки: `NOT_EXECUTED — ожидается подключение к корпоративной сети`.

| ID | Проверка и ожидаемый результат |
|---|---|
| LS-V01 | Проверить уникальность `Document279.ID`/`Document329.ID`, ненулевые границы, ключ кандидата и отсутствие размножения join со справочниками; ожидается одна строка документа до разворота слотов. |
| LS-V02 | Сопоставить влияние `Posted`, `Marked`, `Document313` и статуса ПЗ; ожидается один явно определённый квалифицированный набор неотменённых занятий по каждой ветке. |
| LS-V03 | Развернуть тестовые интервалы на 5-минутные слоты; ожидается `slot_count = duration_minutes / 5`, без слотов за пределами `[start,end)` и без отрицательных/некратных интервалов. |
| LS-V04 | Проверить кардинальность услуги → формат/подразделение и обязательность клуба/зала/тренера; ожидается отсутствие размножения занятия. |
| LS-V05 | Проверить значения `Fld1778`, `Fld3228`, статуса ПЗ и соответствие `InfoRg7006`/`InfoRg8675`; ожидается воспроизводимое распределение платное/клубное время/резерв и число прибывших. |
| LS-V06 | На контрольной выборке воспроизвести current M: `created_at > lesson_end_at` означает `after`; ожидается совпадение распределения с текущей Power BI-моделью. |
| LS-V07 | NOT_APPLICABLE для PostgreSQL: внешние Excel-справочники остаются в Power BI по решению пользователя 2026-07-30. |
| LS-V08 | Сверить по одному периоду и клубу: число занятий, часы занятости, прибытия/посетивших, рейтинг и долю ГП; ожидается согласованное с Power BI контрольное значение. |

Пример SQL-проверки LS-V03 подготовлен, но не исполнялся:

```sql
WITH lessons AS (
  SELECT 'group_lesson'::text AS source_kind, _IDRRef AS source_lesson_id,
         _Fld3218 AS lesson_start_at, _Fld3219 AS lesson_end_at
  FROM _Document279
  WHERE _Fld3218 >= :from_at AND _Fld3218 < :to_at
), slots AS (
  SELECT l.*, s.slot_start_at
  FROM lessons AS l
  CROSS JOIN LATERAL generate_series(
    l.lesson_start_at,
    l.lesson_end_at - interval '5 minutes',
    interval '5 minutes'
  ) AS s(slot_start_at)
)
SELECT source_lesson_id,
       COUNT(*) AS slot_count,
       EXTRACT(epoch FROM (MAX(lesson_end_at) - MIN(lesson_start_at))) / 300 AS expected_slots
FROM slots
GROUP BY source_lesson_id
HAVING COUNT(*) <> EXTRACT(epoch FROM (MAX(lesson_end_at) - MIN(lesson_start_at))) / 300;
```

Параметры и физические имена схемы сверяются перед запуском; проверка не
принимает некратные пяти минутам интервалы как скрытое правило.
