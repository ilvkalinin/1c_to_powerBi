# Source-to-target mapping: «Уроки и расписание»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0015 / SOURCE VALIDATED — SV-LS-001 / SLOT-EDGE POLICY DECISION_REQUIRED`.

Спроектированы `mart.lesson_room_slot_5m` и REUSE `mart.group_lesson`.
Production SQL не создаётся.

История следует `BR-003` (`CONFIRMED — решение пользователя 2026-07-30`).

## Целевые наборы и reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| `REUSE`: групповое занятие | Использовать логический набор «контроль предзаписи: групповое занятие» для `Document279`, вместимости, платных прибывших и бесплатных посетивших. | CONFIRMED reuse: [prebooking mapping](prebooking_control.md) |
| `EXTEND` существующих фактов | `visit_client_day`, `club_day_metrics`, факт ИП и события предзаписи имеют другой grain и не содержат интервал помещения. | REJECTED — CONFIRMED analysis |
| `NEW`: расписание и занятость | `mart.lesson_room_slot_5m`: занятие × 5-минутный слот из `Document279`/`Document329`. | DESIGNED — ADR-0015 |
| Общие измерения | Календарь, клуб, помещение, услуга, сотрудник и вид деятельности — REUSE источников/измерений. | VALIDATED source keys/cardinality — SV-LS-001; orphan references remain NULL |

Гранулярность нового логического набора: одно расписанное занятие из одной
документной ветви, развёрнутое на один 5-минутный интервал. Логический ключ
`(source_kind, source_lesson_id, slot_start_at)` подтверждён для точных
пятиминутных интервалов; граница остальных 855 document rows требует решения.

## Колонки «расписание и занятость зала»

| Целевая колонка | Бизнес-описание | Источник | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `source_kind` | ветвь занятия | `Document279` / `Document329` | явные значения `group_lesson` / `prebooking` | `text` | нет | CONFIRMED agreed rule | LS5-V02 |
| `source_lesson_id` | стабильная ссылка занятия | `Document279._IDRRef` / `Document329._IDRRef` | `encode(..., 'hex')` | `text` | нет | VALIDATED | LS5-V01/02 |
| `created_at` | момент внесения документа | `_Date_Time` обеих таблиц | без округления | `timestamp` | нет | VALIDATED | LS5-V01 |
| `lesson_start_at` | начало занятия | `Document279.Fld3218` / `Document329.Fld4306` | по `source_kind` | `timestamp` | нет | VALIDATED | LS5-V01/02 |
| `lesson_end_at` | окончание занятия | `Document279.Fld3219` / `Document329.Fld4307` | по `source_kind`; интервал `[start,end)` | `timestamp` | нет | VALIDATED for positive 5m intervals | LS5-V02/03 |
| `slot_start_at` | начало 5-минутного занятого интервала | `lesson_start_at`, `lesson_end_at` | серия с шагом 5 мин, начало включено, конец исключён | `timestamp` | нет | DECISION_REQUIRED for 855 source intervals | LS5-V02/03 |
| `club_id` | клуб занятия | `Fld3224` / `Fld4310` | `encode(..., 'hex')`, не описание | `text` | нет | VALIDATED | LS5-V01/04 |
| `room_id` | помещение | `Fld3227` / `Fld4320` | `encode(..., 'hex')`; orphan остаётся NULL | `text` | да | VALIDATED WITH NULL RISK | LS5-V01/04 |
| `employee_id` | ведущий сотрудник | `Fld3223` / `Fld4322` | `encode(..., 'hex')`; orphan остаётся NULL | `text` | да | VALIDATED WITH NULL RISK | LS5-V01/04 |
| `service_id` | услуга | `Fld3226` / `Fld4316` | `encode(..., 'hex')`; orphan остаётся NULL | `text` | да | VALIDATED WITH NULL RISK | LS5-V01/04 |
| `activity_id` | подразделение услуги | `Reference163.Fld1733` → `Reference70.ID` | stable encoded ID; orphan остаётся NULL | `text` | да | VALIDATED WITH NULL RISK | LS5-V04 |
| `training_format_id` | формат тренировки | `Reference163.Fld1803` → `Reference248.ID` | encoded ID; не заменять «Платный урок» текстом | `text` | да | VALIDATED WITH NULL RISK | LS5-V04 |
| `payment_class_current` | клубное время / платное / резерв | `Reference163.Fld1778`, `Document279.Fld3228`, статус ПЗ | branch-specific current rule; не считать универсальным правилом | `text` | да | VALIDATED | LS5-V06 |
| `schedule_entry_timeliness` | внесено до/после контрольного момента | `created_at`, `lesson_start_at`, `lesson_end_at` | `created_at > lesson_end_at` → `after`, ровно как в текущем M | `text` | нет | VALIDATED | LS5-V06 |
| `is_cancelled_current` | отменённое занятие | `Document313`, статусы/флаги документов | current rule различается по веткам; единый фильтр не вводить | `boolean` | UNKNOWN | CONFIRMED separate current-rule qualification | LS5-V02 |

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
| `InfoRg7107` | дежурства | EXCLUDED from this mart | SV-LS-001: 45 733 duty rows; final lessons set excludes their synthetic service |
| внешние `Волшебка_Спр`, `Волшебка__СпрПлощади`, `СПР_Помещения`, параметры УДВ, старая база | вместимость, типы, классификация, история | EXTERNAL / остаются в Power BI, не входят в PostgreSQL mapping | решение пользователя 2026-07-30 |
| `AccumRg7575`, `Document325`, `Reference59`, `Reference141X1` | знаменатель доли ГП | CONFIRMED current source | M; [work attendance mapping](work_attendance.md) |

## Выполненные read-only проверки

| ID | Проверка и ожидаемый результат |
|---|---|
| LS5-V01—V05 | Выполнены 2026-08-14: физические поля, candidate key, интервал, slot sample, cardinality и duty-exclusion. Точные results: [SV-LS-001](../source_metadata/server_validation_2026-08-14.md). |
| LS5-V06 | Классы `club_time`/`paid`/`reserve` и `created_at > lesson_end_at` измерены раздельно для ГЗ и ПЗ; точные values: [SV-LS-001](../source_metadata/server_validation_2026-08-14.md). |
| LS-V07 | NOT_APPLICABLE для PostgreSQL: внешние Excel-справочники остаются в Power BI по решению пользователя 2026-07-30. |
| LS-V08 | Не входит в slot mart: рейтинг и доля ГП остаются DAX-метриками на других grain; внешний Power BI snapshot не является входом Stage 2. |

Слот-контроль из SV-LS-001 использует полный арифметический контроль горизонта
и фактический разворот только контрольной недели, чтобы не материализовать
миллионы строк исключительно ради read-only валидации. Параметры и физические
имена схемы сверены. Некратные пяти минутам интервалы не принимаются как
скрытое правило: их обработка требует отдельного решения.
