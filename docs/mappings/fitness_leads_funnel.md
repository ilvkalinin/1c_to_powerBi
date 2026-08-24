# Source-to-target mapping: воронка лиды фитнес

Статус: `STAGE-2 VALIDATED WITH BLOCKER — task grain is confirmed; a one-row service outcome is not runnable`.
Outcome-атрибуция подтверждена calculated columns текущей модели; физические
ключи, типы, состояния и кардинальности остаются `VALIDATION_PENDING`.

Stage-3 planning 2026-08-24 confirmed `NEW` separate task fact. The
implemented `mart.marketing_funnel_task` is not reusable as data because its
single marketing-funnel scope excludes all four fitness funnels. Its task-fact
pattern is reusable only. Stage-2 now confirms the physical task key,
dimensions, client-code and 45-day source path. `service_name` is `BLOCKER`:
two current tasks are multivalued and 1,432 earliest booking days have DAX
service ties without an approved source-side selector. Evidence:
`docs/source_metadata/fitness_leads_funnel_stage2_validation_2026-08-24.md`.

Гранулярность одной строки базового набора:

> одно CRM-задание `Reference106.ID`.

Логический ключ: `task_id` (`Reference106.ID`; физический тип `UNKNOWN`).

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Grain | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|
| `task_id` | стабильный ключ задания | `Reference106.ID` | без преобразования | bytea source / text target | нет | task | CONFIRMED source | FL-V02 |
| `task_code` | отображаемый код задания | `Reference106.Code` | без преобразования | text | нет | task | CONFIRMED source | FL-V02 |
| `created_at` | дата формирования задания | `Reference106.Fld1193` | без преобразования | timestamp UNKNOWN | нет | task | CONFIRMED source | SQL/M | V-01, V-09 |
| `task_date` | дата ключа календаря | `Reference106.Fld1193` | `created_at::date` | date | нет | task | CONFIRMED current | DAX `ДатаКлюч` | V-01, V-09 |
| `closed_at` | дата закрытия | `Reference106.Fld1192` | без преобразования | timestamp UNKNOWN | да | task | CONFIRMED source | SQL/M | V-01 |
| `forced_closed_at` | дата принудительного закрытия | `Reference106.Fld8772` | без преобразования | timestamp UNKNOWN | да | task | CONFIRMED source | SQL/M | V-01 |
| `funnel_id` | стабильная воронка | `Reference106.Fld1191` | отобрать четыре подтверждённых ID | UNKNOWN | нет | task | CONFIRMED current | SQL/M | V-03 |
| `funnel_name` | название воронки | `Reference89.Description` | join по `funnel_id` | text | нет | task | CONFIRMED current | SQL/M | V-04 |
| `club_id` | клуб задания | `Reference106.Fld1195` | без преобразования | UNKNOWN | да | task | CONFIRMED source | SQL/M | V-04 |
| `club_name` | название клуба | `Reference132.Description` | join по `club_id` | text | да | task | CONFIRMED current | SQL/M | V-04 |
| `network_name` | сеть для среза | `Reference132` через общий mapping клуба | не дублировать mapping в факте; получать по `club_id` | text | да | task | CONFIRMED common rule / physical fields pending | решение пользователя 2026-07-30; source catalog | V-13 |
| `client_key` | стабильный технический клиент | `Reference106.Fld1196` | защищённое представление; способ UNKNOWN | UNKNOWN | да | task | CONFIRMED source / protection UNKNOWN | SQL/M, BR-007 | V-04, V-13 |
| `client_code` | код клиента | `Reference141X1.Code` | join по `client_key` | text | да | task | CONFIRMED current | SQL/M | V-04 |
| `client_name`, `client_phone` | PII детального набора | `Reference141X1.Description`, `Fld1531` | не включать в Power BI без подтверждённого потребителя | text | да | task | CONFIRMED current source / consumer UNKNOWN | SQL/M | V-13 |
| `tenure_type` | New / Ex / Renew | `Reference106.Fld1190` | current GUID mapping | text | да | task | CONFIRMED current | SQL/M | V-07 |
| `campaign_id`, `campaign_name` | маркетинговая кампания | `Fld1197 → Reference145.ID/Description` | join | UNKNOWN, text | да | task | CONFIRMED current | SQL/M | V-04 |
| `parent_campaign_name` | родитель кампании | `Reference145.ParentID → Reference145.Description` | `NULL → «НетРодителя»` только для current visual classification | text | да | task | CONFIRMED current | M | V-04 |
| `task_description` | описание задания | `Reference106.Fld1200` | `varchar(1000)` в current SQL | text | да | task | CONFIRMED source | SQL/M | V-01 |
| `unsuccessful_reason` | причина неуспеха | `Fld1201 → Reference201.Description` | исключить два exact значения дубля | text | да | task | CONFIRMED current | SQL/M | V-03 |
| `funnel_stage_name` | этап воронки | `Fld1205 → Reference264.Description` | join | text | да | task | CONFIRMED current | SQL/M | V-04 |
| `first_interaction_type` | тип первого взаимодействия | `Reference106.Fld8712` | current GUID mapping, затем M-classification | text | да | task | CONFIRMED current | SQL/M | V-07 |
| `service_name` | итоговая услуга для среза | current `Задания[Услуга]` либо `Записи.НаименованиеУслуги` | current DAX is preserved; no one-value selector is approved | text | да | task | BLOCKER | FL-V05/V06/V09 | separate business decision |
| `task_count` | вклад задания в число заданий | `task_id` | `1`; для меры distinct key | smallint | нет | task | CONFIRMED by design | DAX | V-02, V-11 |
| `has_booking` | есть запись по заданию | `Reference106.Fld1205 → Reference264.Description` | `true` для шести current stage names, иначе `false` | boolean | нет | task | CONFIRMED current | DAX `Есть запись` | V-07, V-11 |
| `training_count` | тренировки, атрибутированные заданию | stage, `Reference141X1.Code`, `ДПФУ факт` | `1` для трёх stages «Пришел…»; иначе `0` для двух ДСУ-воронок; иначе `SUM(ДПФУ факт.КоличествоЗаписей)` того же клиента в `[task_date; task_date + 45]` включительно | bigint | current PBIT may return blank | task | CONFIRMED current and physical source | FL-V08/V09/V11 |
| `has_paid_training_45d` | клиент пришёл на тренировку по текущей модели | `training_count` | `training_count > 0` | boolean | нет | task | CONFIRMED current | DAX `ПришелНаТренировку` | V-09, V-11 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `Reference106`, `Reference89`, `Reference141X1`, `Reference132`, `Reference145`, `Reference201`, `Reference264` | CRM-задание и его атрибуты | CONFIRMED current source | `Задания 2026` |
| `InfoRg7006`, `Document329`, `Document279`, `Document329.VT4352`, `Reference163`, `Enum448` | текущие записи/услуги/тренировки | CONFIRMED current sources; key/state pending | `Записи`, `ИП`, `Задания 2026` |
| `AccumRg7575`, `AccumRg7646`, `Reference70` | текущий агрегат ДПФУ для `training_count` | CONFIRMED current sources; technical key/state pending | `ДПФУ факт` и DAX |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `docs/catalogs/source_objects.md` | CRM, записи, тренировки ИП и ДПФУ уже каталогизированы; физические ключи/состояния не подтверждены. | CONFIRMED catalog / validation pending |
| Проверенные продукты из `docs/catalogs/data_products.md` | `UNKNOWN — взаимодействия отдела продаж`, факт тренировок ИП, логический факт ДПФУ. | CONFIRMED catalog |
| Проверенные правила из `docs/catalogs/business_rules.md` | BR-001 компактное извлечение, BR-002 reuse по grain, BR-007 protected client key, BR-009 тренировки ИП. | CONFIRMED |
| Сравнение гранулярности | CRM-взаимодействия: interaction; ИП: training; ДПФУ: service movement. Отчёту нужен task. | CONFIRMED mismatch |
| Сравнение ключей | `interaction_id`, `(training_date, club, employee, client, service)` и ключ движения не эквивалентны `task_id`. | CONFIRMED mismatch |
| Сравнение бизнес-семантики | Задания — когорта конверсии; существующие продукты — события/движения. Текущая атрибуция client-code + date interval подтверждена, но не меняет grain базового факта. | CONFIRMED |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | `NEW`: `mart.fitness_leads_funnel_task`, компактный task-level факт для текущего отчёта; возможное общее CRM task-core для других отчётов не утверждено. | ACCEPTED — user 2026-07-29 / ADR-0011 |
| Причина решения | `REUSE` создаст размножение task; `EXTEND` событий ИП/ДПФУ смешает grain. | CONFIRMED |
| Затронутые существующие потребители | «Загрузка сотрудников» (общий CRM-домен), «Фитнес воронка», «Новички и гостевые визиты», маркетинговая «Воронка» — последние три пока только потенциальные. | ASSUMPTION; `sales_team_workload.md` |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| VALIDATION_PENDING | `task → service` | current SQL может дать `1:N` услуг по закрытию + коду клиента; fallback использует DAX `MIN` без documented priority. | V-05/V-06/V-09; при не-`1:1` пересмотреть модель услуги. |
| VALIDATION_PENDING | client-code attribution | Outcome связываются по отображаемому коду клиента, а не ID. | V-08: уникальность, NULL, стабильность и совпадение представления кода. |
| VALIDATION_PENDING | сеть | Общий mapping клуба подтверждён; физические поля и покрытие клубов ещё не проверены. | V-13. |
| UNKNOWN | PII-потребитель | SQL извлекает ФИО и телефон, визуалы их не показывают. | Подтвердить потребителя или исключить из будущего контракта. |
| VALIDATION_PENDING | ключи, NULL, состояния, timestamps, объём | Физическая metadata и правила 1С не проверены. | V-01–V-07, V-10–V-13. |

`SV-078` (live read-only, 2026-08-11) подтвердил bounded current task-to-
service join: 100 задач → 100 строк, без join excess; у 82 задач отсутствует
raw client-day match. Это не меняет stage-based семантику `Есть запись`.
SV-072 дополнительно подтверждает технический ключ `InfoRg7006` и фиксирует
legacy one-to-many `Document329.VT4352`. Полный task-scan, service fallback,
стабильность client-code и source states остаются `VALIDATION_PENDING`.
