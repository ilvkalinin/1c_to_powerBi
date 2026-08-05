# Source-to-target mapping: «Контроль предварительной записи»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0015 / TECHNICAL VALIDATION DEFERRED`.
Спроектированы `mart.prebooking_state_event`, REUSE
`mart.dpfu_plan_assignment` и `mart.group_lesson`; DDL не создаётся.

## Целевые наборы и гранулярность

| Логический набор | Одна целевая строка | Логический ключ | Назначение |
|---|---|---|---|
| `mart.prebooking_state_event` | одно событие состояния одной записи | кандидат `(state_period, recorder_id, line_no)` | своевременность, нетто-записи, отмены и детализация клиента |
| `mart.dpfu_plan_assignment` | дата плана × клуб × подразделение × тренер × плановый клиент | состав ссылок и `InfoRg6612`-ключ `UNKNOWN` | REUSE общего детального плана |
| `mart.group_lesson` | одно групповое занятие | `Document279.ID` кандидат | вместимость, активные записи и пришедшие |

Кандидаты ключей не являются подтверждёнными до серверной валидации.

## События контроля предварительной записи

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `state_event_at` | время состояния/отмены | `InfoRg7006.Period` | без замены на дату документа | `timestamp` `UNKNOWN` | нет | CONFIRMED current | PC-V01, PC-V02 |
| `booking_document_id` | стабильная ссылка исходной записи | `InfoRg7006.Fld7007` | сохранить технически до source-side дедупликации | `UNKNOWN` | нет | CONFIRMED current | PC-V03 |
| `booking_kind` | персональная или групповая ветка | тип `Fld7007` → `Document329` / `Document279` | явная константа после проверки полиморфной ссылки | `text` | нет | CONFIRMED need | PC-V03 |
| `lesson_start_at` | начало занятия | `Document329.Fld4306` / `Document279.Fld3218` | выбрать по `booking_kind` | `timestamp` `UNKNOWN` | нет | CONFIRMED current | PC-V03, PC-V04 |
| `lesson_end_at` | окончание занятия | `Document329.Fld4307` / `Document279.Fld3219` | выбрать по ветке | `timestamp` `UNKNOWN` | нет | CONFIRMED current | PC-V03, PC-V04 |
| `club_id` | клуб занятия | `InfoRg7006.Fld7009`; сверить с документом | стабильный ID, не имя | `UNKNOWN` | нет | CONFIRMED current | PC-V03, PC-V05 |
| `activity_id` | вид деятельности | услуга документа → `Reference163.Fld1733` → `Reference70.ID` | стабильный ID | `UNKNOWN` | да | CONFIRMED current | PC-V05 |
| `employee_id` | сотрудник занятия | `Document329.Fld4322` / `Document279.Fld3223` | стабильный ID | `UNKNOWN` | нет | CONFIRMED current | PC-V04 |
| `service_id` | услуга записи | `InfoRg7006.Fld7010` и услуга документа | текущий M требует сверки совпадения | `UNKNOWN` | нет | CONFIRMED current | PC-V05 |
| `client_key` | стабильный клиент для счёта и связи с визитом | `InfoRg7006.Fld7008` | защищённый стабильный ключ; исходный ID не выгружать без потребителя | `UNKNOWN` | нет | CONFIRMED need | PC-V06 |
| `client_code` | код клиента в детальной отмене | `Reference141X1.Code` | только PII-доступный detail | `text` | да | CONFIRMED current | PC-V06 |
| `client_name` | ФИО клиента в детальной отмене | `Reference141X1.Description` | только PII-доступный detail | `text` | да | CONFIRMED current | PC-V06 |
| `state_order` | текущее состояние записи | `Enum448.EnumOrder` через `InfoRg7006.Fld7013` | сохранить порядок и расшифровку | `smallint` | нет | CONFIRMED current | PC-V07 |
| `event_category` | категория для DAX-меры | время события против `lesson_start_at`, `lesson_end_at` и следующей полуночи | `before_previous_day_cutoff`, `before_lesson_end`, `after_lesson_end`, `next_day`, `cancel_before_cutoff`, `cancel_after_cutoff` | `text` | нет | CONFIRMED current | PC-V08 |
| `booking_delta` | вклад состояния в нетто-записи | состояние 1 = `+1`; 2/3 = `-1`; остальные не участвуют в данной мере | не использовать без PC-V07 | `smallint` | нет | CONFIRMED current | PC-V07, PC-V08 |
| `cancelled_before_lesson` | отмена произведена до старта занятия | `state_event_at < lesson_start_at` | для страницы отмен | `boolean` | да | CONFIRMED current | PC-V08 |
| `is_paid_booking` | строка соответствует текущему отбору платной записи | ветка ПЗ: исключения купона, ИП и взаиморасчёта с сотрудником; ветка ГП: `Document279.Fld3228 = 1` | сохранить branch-specific rule, не заменять текстовым фильтром | `boolean` | нет | CONFIRMED current / technical join pending | PC-V05, PC-V09 |

## Назначения текущего плана ДПФУ

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `plan_date` | дата плановой тренировки | `InfoRg6612.Fld6613` | календарная дата | `date` | нет | CONFIRMED current | PC-V10 |
| `club_id` | клуб плана | `InfoRg6612.Fld6615` | стабильный ID | `UNKNOWN` | нет | CONFIRMED current | PC-V10 |
| `activity_id` | подразделение плана | `InfoRg6612.Fld6614` → `Reference217.ID` | стабильный ID | `UNKNOWN` | да | CONFIRMED current | PC-V10 |
| `employee_id` | тренер плана | `InfoRg6612.Fld6616` → `Reference225.ID` | стабильный ID, не имя | `UNKNOWN` | да | CONFIRMED current | PC-V10 |
| `planned_client_key` | плановый клиент/назначение | `InfoRg6612.Fld6619` | защищённый ключ | `UNKNOWN` | да | CONFIRMED current | PC-V10 |
| `planned_service_count` | вклад в план количества услуг | `Fld6619 IS NOT NULL` | `1`; будущий итог — `COUNT(planned_client_key)` как в DAX | `smallint` | нет | CONFIRMED current | PC-V10 |
| `planned_revenue` | стоимость плановой тренировки | `InfoRg6612.Fld6620` | отдельная мера; не заменяет число услуг | `numeric` | да | CONFIRMED source / consumer pending | PC-V10 |

## Вместимость группового занятия

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `group_lesson_id` | ссылка группового занятия | `Document279.ID` | кандидат стабильного ключа | `UNKNOWN` | нет | CONFIRMED current | PC-V11 |
| `lesson_start_at` / `lesson_end_at` | границы урока | `Document279.Fld3218` / `Fld3219` | без округления | `timestamp` `UNKNOWN` | нет | CONFIRMED current | PC-V11 |
| `club_id`, `employee_id`, `service_id`, `activity_id` | разрезы занятия | `Document279.Fld3224/3223/3226`; услуга → вид деятельности | стабильные IDs | `UNKNOWN` | нет | CONFIRMED current | PC-V11 |
| `capacity` | вместимость урока | `Document279.Fld3222` | без замены `NULL` на ноль | `integer` `UNKNOWN` | да | CONFIRMED current | PC-V11 |
| `active_booking_count` | неотменённые записи | `InfoRg7006`, status 1/2/3 | сумма `+1/-1` после проверки ключа | `bigint` | нет | CONFIRMED current | PC-V11, PC-V12 |
| `arrived_count` | пришедшие на платную ГП | `InfoRg7006`, status 4 | число логических записей | `bigint` | да | CONFIRMED current | PC-V07, PC-V12 |
| `free_program_arrived_count` | пришедшие бесплатной ГП | `InfoRg8675.Fld8677` | применять только к бесплатной ветке | `bigint` | да | CONFIRMED current | PC-V12 |
| `prepayment_type` | платное / бесплатное | `Document279.Fld3228` | расшифровку значений подтвердить | `smallint` `UNKNOWN` | нет | CONFIRMED current | PC-V11 |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `docs/catalogs/source_objects.md` | `InfoRg7006`, `Document329`, `Document279`, `InfoRg8675`, `InfoRg6612`, `Reference132`, `Reference141X1`, `Reference163`, `Reference217`, `Reference225`, `Enum448` уже известны; `Document329.VT4352` — риск one-to-many. | CONFIRMED catalog, metadata, M |
| Проверенные продукты из `docs/catalogs/data_products.md` | `mart.dpfu_plan_assignment`, `mart.ip_training_daily`, `mart.visit_client_day` и `mart.club_day_metrics` рассмотрены. | CONFIRMED catalog |
| Проверенные правила из `docs/catalogs/business_rules.md` | BR-002, BR-003, BR-004 и BR-013 применимы; только BR-003 подтверждает исторический горизонт. | CONFIRMED catalog |
| Сравнение гранулярности | У плана есть тренер/клиент, у события — момент смены статуса, у групповой вместимости — занятие; они отличаются также от дневного агрегата планов и client-day. | CONFIRMED M/DAX |
| Сравнение ключей | Все технические ключи и кардинальности остаются неподтверждёнными. | VALIDATION_PENDING |
| Сравнение бизнес-семантики | Факт тренировок ИП отражает оказание услуги, не своевременность записи; агрегированный план ДПФУ не хранит тренера/клиента. | CONFIRMED M/DAX |
| Решение | `NEW` для событий и группового занятия; `REUSE` детального `mart.dpfu_plan_assignment`, календаря и измерений. | DESIGNED — ADR-0015 |
| Причина решения | Расширение существующих фактов смешало бы несовместимые grain и изменило бы их действующую семантику. | CONFIRMED |
| Затронутые существующие потребители | ДПФУ, ИП, Посещения Физкульт и Уроки/расписание. | CONFIRMED — ADR-0015 |

## Риски и будущая валидация

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| VALIDATION_PENDING | `InfoRg7006` | Не доказаны ключ, историчность статусов, `Active` и коды enum. | PC-V02, PC-V07; `NOT_EXECUTED — ожидается подключение к корпоративной сети`. |
| VALIDATION_PENDING | `InfoRg7006 → Document279/329` | Полиморфная ссылка может иметь orphan или обе ветки; поля клуба/услуги могут расходиться. | PC-V03–PC-V05; `NOT_EXECUTED — ожидается подключение к корпоративной сети`. |
| VALIDATION_PENDING | `Document329.VT4352` | Current M соединяет её без номера строки; возможное размножение событий. | PC-V09; `NOT_EXECUTED — ожидается подключение к корпоративной сети`. |
| VALIDATION_PENDING | состояния документов | Текущий M не применяет единое подтверждённое правило `Posted`/`Marked`. | PC-V04; `NOT_EXECUTED — ожидается подключение к корпоративной сети`. |
| VALIDATION_PENDING | PII клиента | Код/ФИО доступны всем пользователям с доступом к отчёту по BR-017; связка с посещением и техническое применение permissions/RLS требуют проверки. | PC-V06, PC-V13; `NOT_EXECUTED — ожидается подключение к корпоративной сети`. |
| VALIDATION_PENDING | план и групповые итоги | Не доказаны ключ плана, `Active`, вместимость и отсутствие повторного подсчёта. | PC-V10–PC-V12; `NOT_EXECUTED — ожидается подключение к корпоративной сети`. |
