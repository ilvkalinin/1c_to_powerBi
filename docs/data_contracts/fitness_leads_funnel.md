# Data contract: «Воронка. Лиды. Фитнес»

Статус: `STAGE-2 VALIDATED WITH BLOCKER / separate task-fact contract retained / no implementation SQL`.
SV-078 подтвердил bounded task-to-service join без размножения строк, но не
полный task-scan, физические типы, client-code attribution или source states.
Контракт проектный; физических объектов не создавалось.

Planning 2026-08-24 confirmed that the implemented marketing task mart cannot
be reused physically because it contains a different funnel scope. This
contract remains the minimal separate task fact, but the source-side outcome
columns are not runnable until the read-only controls named in
[`planning`](../reports/fitness_leads_funnel_stage_3_planning.md) are closed.

## Общие параметры

| Параметр | Значение | Статус / доказательство |
|---|---|---|
| Объект PostgreSQL | `mart.fitness_leads_funnel_task` | ACCEPTED — ADR-0011 |
| Таблица Power BI | `Задания` | CONFIRMED — текущий DAX |
| Назначение | задания четырёх фитнес-воронок и fixed task-level конверсии | CONFIRMED |
| Гранулярность строки | одно CRM-задание `Reference106.ID` | CONFIRMED — mapping/ADR |
| Логический ключ | `task_id` | VALIDATION_PENDING — V-02 |
| Период хранения | BR-003 | CONFIRMED |
| Режим и правила обновления | атомарный полный пересчёт согласованного горизонта ежедневно | ACCEPTED design / решение пользователя 2026-07-30; техническая валидация pending |
| SLA | данные доступны не позднее 08:30 по Москве | CONFIRMED — BR-014, решение пользователя 2026-07-30 |
| Исправления и удаления | попадают в полный пересчёт горизонта; фактические states/окно изменений pending | ACCEPTED design / V-07, V-12 |
| Таблица дат | `_СпрДата` / `Календарь` | CONFIRMED current model |
| Поле даты витрины | `task_date` / `ДатаКлюч` | CONFIRMED — DAX |
| Правила фильтрации по дате | дата создания задания; ПГ — `SAMEPERIODLASTYEAR` | CONFIRMED — DAX |
| Поле инкрементального обновления | отсутствует | UNKNOWN — нет надёжного watermark |
| Режим Power BI | `Import` готового факта | ACCEPTED design; current storage mode technical verification pending |

## Колонки

Технические идентификаторы — канонический `text` в витрине. Это целевой
контракт, а не утверждение о физическом типе источника 1С; его conversion
проверяется V-01/V-02.

| Колонка PostgreSQL | Поле Power BI | PostgreSQL тип | Power BI тип | NULL | Роль | Аддитивность | Скрыть | Mapping |
|---|---|---|---|---|---|---|---|---|
| `task_id` | `ID задания` | text | Text | нет | ключ факта | не мера | да | `task_id` |
| `task_code` | `КодЗадания` | text | Text | нет | отображаемый идентификатор | не мера | да | `task_code` |
| `task_date` | `ДатаКлюч` | date | Date | нет | FK календаря | не мера | нет | `task_date` |
| `club_id` | `Код клуба` | text | Text | да | FK клуба | не мера | да | `club_id` |
| `club_name` | `Клуб` | text | Text | да | срез/отображение | не мера | нет | `club_name` |
| `funnel_id` | `ID воронки` | text | Text | нет | технический разрез | не мера | да | `funnel_id` |
| `funnel_name` | `Воронка` | text | Text | нет | срез/строка визуала | не мера | нет | `funnel_name` |
| `campaign_id` | `ID кампании` | text | Text | да | технический разрез | не мера | да | `campaign_id` |
| `campaign_name` | `МаркетинговаяКампания` | text | Text | да | срез/строка визуала | не мера | нет | `campaign_name` |
| `tenure_type` | `ВидСтажа` | text | Text | да | срез | не мера | нет | `tenure_type` |
| `first_interaction_type` | `ТипПервогоВзаимодействия` | text | Text | да | срез/строка визуала | не мера | нет | `first_interaction_type` |
| `service_name` | `УслугаИтог` | text | Text | да | срез | не мера | нет | `service_name` |
| `has_booking` | `Есть запись` | boolean | True/False | нет | task-level признак | не суммировать напрямую | да | `has_booking` |
| `training_count` | `КоличествоТренировок` | bigint | Whole number | нет | показатель | аддитивен по task-grain; сохраняет перекрытие окон | нет | `training_count` |
| `has_paid_training_45d` | `ПришелНаТренировку` | boolean | True/False | нет | task-level признак | не суммировать напрямую | да | `has_paid_training_45d` |

`client_code`, `client_key`, ФИО, телефон, описание задания, даты закрытия,
этап и причина неуспеха применяются source-side либо не имеют подтверждённого
потребителя в показанных визуалах. В Power BI контракт не входят. Добавление
возможно только через mapping и пересмотр PII-доступа.

## Связи

| От объекта/поля | К объекту/полю | Кардинальность | Направление фильтрации | Статус / доказательство |
|---|---|---|---|---|
| `_СпрДата[Date]` | `Задания[ДатаКлюч]` | `1:*` | односторонняя к факту | CONFIRMED current relationship; uniqueness date pending |
| `_СпрКлубы[Код клуба]` | `Задания[Код клуба]` | `1:*` | односторонняя к факту | ACCEPTED contract; current model links by name, ID relation requires V-13 |
| `_СпрСтажи[ВидСтажа]` | `Задания[ВидСтажа]` | `1:*` | односторонняя к факту | CONFIRMED current relationship; dimension uniqueness pending |
| `_Маркетинговые кампании[МаркетинговаяКампания]` | `Задания[МаркетинговаяКампания]` | `1:*` | односторонняя к факту | CONFIRMED current relationship; unique name pending |
| `_ТипыВзаимодействий[ТипВзаимодействия]` | `Задания[ТипПервогоВзаимодействия]` | `1:*` | односторонняя к факту | CONFIRMED current relationship; unique value pending |

Срез `Сеть` должен поступать из справочника клубов. Создавать связь
fact-to-fact с `ДПФУ факт`, `Записи` или `ИП` запрещено: текущая client/date
атрибуция уже материализована в task-level полях. Для `УслугаИтог` допустим
прямой срез факта; отдельный справочник услуг не создаётся до доказательства
стабильного service key.

## Граница PostgreSQL и Power BI

PostgreSQL: фильтры источника и состояний после их подтверждения, отбор
воронок, исключение дублей, CRM-классификации, client-code/date outcome-логика,
`has_booking`, `training_count`, `has_paid_training_45d` и `service_name`.

Power Query: только Import факта, типизация и подключение к малым
справочникам. Никаких ODBC-запросов к сырым CRM/регистрам, merge по клиенту и
дате или крупных группировок.

DAX: distinct число заданий, число задач с признаками, конверсии, ПГ,
накопительный итог и отображение нулей. Планового показателя и плановых
визуалов нет (решение пользователя 2026-07-30). Расчёт `training_count`
повторно в DAX не реализуется.

## Условия принятия

1. `task_id` уникален, строка факта не размножается current join услуги.
2. Коды клиентов имеют однозначное и стабильное представление во всех трёх
   current наборах; NULL и orphan-задачи обработаны по подтверждённому правилу.
3. V-07 подтверждает допустимые `Active`/`Posted`/`Marked`, удаления и отмены.
4. V-09 сверяет включающие границы 45 дней, закрытие до создания, 29 февраля
   и несколько задач одного клиента с пересекающимися окнами.
5. V-11 воспроизводит контрольные значения Power BI; V-12 — rerun,
   изменения/удаления, объём и SLA.
6. Power BI подтверждает все `1:*` связи, отсутствие M2M и корректный ПГ.
