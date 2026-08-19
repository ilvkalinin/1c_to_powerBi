# Source-to-target mapping: «Новички и гостевые визиты»

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION VALIDATED WITH PRESERVED RISKS — SV-087, SV-097, SV-102, SV-106, SV-108, SV-109 / IMPLEMENTATION DEFERRED`.

Ниже описаны наборы, для которых ADR-0020 проектирует
`mart.new_first_visit`, `mart.guest_visit_conversion` и REUSE
`mart.v_guest_tour`. Это не разрешение на SQL/DDL. NV-V01—V09 выполнены
read-only controls: источники, ACCUNIQ scope, current latest-state path,
первый визит и границы 0/44/45 подтверждены. Technical key гостевого регистра
уникален, но candidate business key имеет дубликаты; ties и final current
`Distinct` сохраняются по BR-018. Пользователь 2026-08-18 утвердил
PBIT-правило ACCUNIQ как базу первого релиза.
SV-006 подтвердил наличие `InfoRg7064`; реестр отсутствующих объектов не
изменяется.
SV-097 дополнительно подтвердил bounded путь документ посещения → движение →
контракт без потери или расхождения клиента. Пользователь 2026-08-18 утвердил
`Pbit_old/Новички и гостевые визиты.pbit` (SHA-256
`3d54a392bec0d3feed21f998c91bf4607886ca101eac7b0adc94d6bbce180796`) как
базу правила: 12 service codes, знаковая нормализация `Fld7585` и итог 1/2.

История следует `BR-003`; refresh — ежедневно (`CONFIRMED — решение
пользователя 2026-07-30`).

## Подтверждённые источники

| Объект | Роль | Статус / доказательство |
|---|---|---|
| `AccumRg7575`, `Document325`, `Reference59` | первое посещение, ACCUNIQ, связь с контрактом | CONFIRMED current source; ключи/состояния pending |
| `InfoRg7064` | статус/регистрация гостевого визита | CONFIRMED current source из M; семантика pending |
| `InfoRg5654` | история стажа гостя | CONFIRMED current source; as-of tie-break pending |
| `Reference141X1`, `Reference132`, `Reference163` | клиент, клуб, услуга | CONFIRMED current physical source; типы/ключи pending |
| `Reference67`, `Reference106`, `InfoRg7146`, `Reference89`, `Reference224`, `Reference225` | тур, задача CRM, телефонная дата, воронка, состояния, исполнитель | CONFIRMED current source; cardinality/semantics pending |
| `InfoRg7006`, `Document329`, `Enum448` | запись на ACCUNIQ для тура | CONFIRMED current source; grain/predicate pending |
| Google Sheets `Апрель - для Ильи план` | внешний план встреч | CONFIRMED external current source; schema/key pending |

## Набор 1: первые посещения New

Гранулярность: `contract_id × первое квалифицированное посещение`; ключ и
tie-break `VALIDATION_PENDING`.

| Целевое поле | Описание / преобразование | PostgreSQL тип | NULL | Статус и проверка |
|---|---|---|---|---|
| `contract_id` | `AccumRg7575.Fld7578 → Reference59.ID` | `uuid`/`bytea` UNKNOWN | нет | CONFIRMED source / V-02 |
| `first_visit_date` | минимальный `AccumRg7575.Period::date` по контракту после квалификации | `date` | нет | CONFIRMED current rule / V-02 |
| `visit_club_id` | `AccumRg7575.Fld7577 → Reference132.ID` | UNKNOWN | да | CONFIRMED current source / V-02 |
| `client_id` | `Document325.Fld4171 → Reference141X1.ID` | UNKNOWN | нет | CONFIRMED current source / V-01 |
| `client_code`, `client_name` | код и ФИО в текущей детализации первых посещений | `Reference141X1.Code`, `Reference141X1.Description` | `text`, `text` | да | CONFIRMED current consumer / PII разрешены пользователем 2026-07-30; V-01 |
| `sex` | `Reference141X1.Fld1527` → Женский/Мужской | `text` | да | CONFIRMED current rule / V-01 |
| `birth_date` | `Reference141X1.Fld1507` | `date` | да | CONFIRMED current source / V-01 |
| `age_at_visit` | полный возраст на `first_visit_date` | `integer` | да | CONFIRMED — решение пользователя 2026-07-30; V-01 |
| `age_group` | дети / юниоры / взрослые | для абонемента — возрастная категория номенклатуры контракта; без абонемента — возраст клиента на дату события | `text` | да | CONFIRMED — решение пользователя 2026-07-30 | V-01 |
| `tenure_type` | `Reference59.Fld694 = New` | `text` | нет | CONFIRMED current filter / V-01 |

Исключения текущего SQL: ДРЦ/УК, ИП, сотрудники, неклиенты. Их GUID и
текстовые фильтры технически подтверждаются в V-01/V-02; текст не становится
production-правилом без этой проверки.

## Набор 2: гостевой визит и конверсия

Гранулярность current output: гость × дата гостевого визита; candidate key
`(guest_registration_id, client_id, guest_visit_date)` имеет 111 578 групп
дубликатов по SV-087. Current M завершает ветку `Distinct(client code, visit
date)`; этот результат сохраняется по BR-018, новый порядок строк не вводится.

| Целевое поле | Описание / преобразование | PostgreSQL тип | NULL | Статус и проверка |
|---|---|---|---|---|
| `guest_registration_id` | `InfoRg7064.Fld7066` | UNKNOWN | да | CONFIRMED source / V-03,V-04 |
| `guest_visit_status_id` | `InfoRg7064.Fld7067` | UNKNOWN | да | CONFIRMED source / V-03 |
| `registered_at` | `InfoRg7064.Period` | `timestamp` UNKNOWN | нет | CONFIRMED source / V-03 |
| `guest_visit_date` | `InfoRg7064.Fld7068::date` | `date` | нет | CONFIRMED source / V-03 |
| `club_id` | `InfoRg7064.Recorder → Document325.Fld4167` | UNKNOWN | да | CONFIRMED current join / V-02,V-03 |
| `client_id` | `InfoRg7064.Fld7065 → Reference141X1.ID` | UNKNOWN | нет | CONFIRMED source / V-03 |
| `client_code`, `client_name` | код и ФИО в текущей детализации гостевых визитов | `Reference141X1.Code`, `Reference141X1.Description` | `text`, `text` | да | CONFIRMED current consumer / PII разрешены пользователем 2026-07-30; V-03 |
| `tenure_at_registration` | latest `InfoRg5654` before `registered_at` | `text` | UNKNOWN | CONFIRMED current rule / V-07 |
| `accuniq_same_day_flag` | exists `AccumRg7575` after 2025-01-01 for client and `Period::date = guest_visit_date`, `Reference163.Code` in 12-code PBIT list; grouped signed `Fld7585` total is 1 or 2 | `boolean` | нет | CONFIRMED user-approved PBIT rule / V-05 physical |
| `accuniq_date` | дата квалифицированного ACCUNIQ | `date` | да | CONFIRMED current target / V-05 |
| `purchase_contract_id` | первый подходящий `Reference59` в окне `[0,44]` дней | UNKNOWN | да | CONFIRMED current rule / V-06 |
| `purchase_activation_date` | `Reference59.Fld670::date` выбранного контракта | `date` | да | CONFIRMED current rule / V-06 |
| `purchase_lag_days` | `purchase_activation_date - guest_visit_date` | `integer` | да | CONFIRMED current rule / V-06 |
| `sex`, `birth_date`, `age_at_guest_visit`, `age_group` | из клиента; возраст и категория на дату гостевого визита, так как на событии нет абонемента | `text`, `date`, `integer`, `text` | да | CONFIRMED — решение пользователя 2026-07-30 |

## Набор 3: тур и конверсия

Гранулярность: одно CRM-взаимодействие `Reference67.ID`. Выбран `EXTEND`
общего logical CRM-core, а не новый общий факт: фильтр воронки, тип встречи и
outcomes данного отчёта локальны.

| Целевое поле | Описание / преобразование | PostgreSQL тип | NULL | Статус и проверка |
|---|---|---|---|---|
| `interaction_id` | `Reference67.ID` | UNKNOWN | нет | CONFIRMED source / V-01,V-08 |
| `tour_date` | `COALESCE(InfoRg7146.Fld7150, Reference67.Fld820)::date` | `date` | нет | CONFIRMED current rule / V-08 |
| `task_id`, `client_id`, `club_id` | `Reference67.Owner → Reference106` поля задачи | UNKNOWN | нет/UNKNOWN | CONFIRMED current join / V-08 |
| `client_code`, `client_name`, `client_phone` | код, ФИО и телефон в текущей детализации туров | `Reference141X1.Code`, `Reference141X1.Description`, `Reference141X1.Fld1531` | `text`, `text`, `text` | да | CONFIRMED current consumer / PII разрешены пользователем 2026-07-30; V-08 |
| `interaction_state`, `interaction_status` | `Reference224` + GUID status `Reference67.Fld830` | `text` | да | CONFIRMED current rule / V-08 |
| `tour_kind` | completed: Закрыто/Выполнено; planned: Запланировано/Не выполнено | `text` | нет | CONFIRMED current rule / V-08 |
| `performer_id` | `Reference67.Fld824 → Reference225.ID` | UNKNOWN | да | CONFIRMED source / V-08 |
| `accuniq_booking_flag` | current `InfoRg7006`/`Document329` match client × `tour_date`, latest state excluding 2/3 | `boolean` | нет | CONFIRMED current rule / NV-V09 physical path; 8 latest ties and 128 client-date duplicate excess preserved |
| `purchase_contract_id`, `purchase_activation_date`, `purchase_lag_days` | первый подходящий контракт в окне `[tour_date, tour_date + 44]` | UNKNOWN, `date`, `integer` | да | CONFIRMED current rule / V-06 |
| `sex`, `birth_date`, `age_at_tour`, `age_group` | из клиента; возраст и категория на дату тура, так как на событии нет абонемента | `text`, `date`, `integer`, `text` | да | CONFIRMED — решение пользователя 2026-07-30 |

## Reuse review

| Кандидат | Сравнение | Решение |
|---|---|---|
| `mart.visit_client_day` | date × actual club × client; не хранит contract/first rank/guest state | REUSE источников только |
| `mart.newcomer_engagement_milestone` | contract × client × fixed checkpoint; другой временной смысл | NOT_APPLICABLE |
| `mart.crm_interaction` | тот же `Reference67.ID` grain | REUSE core через `mart.v_guest_tour` — ADR-0016/0020 |
| факт тренировок ИП/предзапись | другой grain и критерий ACCUNIQ | REUSE источников только |
| `mart.new_first_visit`, `mart.guest_visit_conversion` | PII-детализация подтверждена; ключи и состояния требуют валидации | DESIGNED — ADR-0020 / implementation deferred |

## Не переносить и границы ответственности

- Внешний план и DAX план-факт не входят в PostgreSQL mart.
- Конверсии, distinct-счётчики, выбор периода и `TODAY()`-зависимый план
  остаются мерами Power BI.
- ФИО и код клиента сохраняются для текущих детальных таблиц, телефон —
  только для детализации туров. Они не участвуют в расчёте KPI, но включены
  по решению пользователя 2026-07-30; права Power BI должны соответствовать
  текущему доступу к отчёту.
- Сырые `AccumRg7575`, `InfoRg7064`, `InfoRg7006` и CRM-регистры не
  реплицируются; требуемые пересечения/агрегации выполняются source-side.

## Результат Stage 2

- NV-V01/V03/V04/V07/V08 (SV-087): источники, technical keys, guest candidate
  duplicates, history и CRM-tour path.
- NV-V05 (SV-102): точные 12 ACCUNIQ-кодов, current sign и группы 1/2.
- NV-V06 (SV-108): окно конверсии `[0,44]`, без включения дня 45.
- NV-V09 (SV-106): current latest-state selection с сохранёнными ties и
  дубликатами `клиент × дата`.
- NV-V02 (SV-109): current первый визит на июле 2026 с 35 ties раннего
  timestamp; второй порядок не добавлен.

Ключи, ties, дубликаты и source multiplicity сохранены как current behavior;
новая методика, DDL/DML и Stage 3 этим mapping не разрешаются.
