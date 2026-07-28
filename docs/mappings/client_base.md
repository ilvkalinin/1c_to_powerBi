# Source-to-target mapping: агрегированный снимок «Клиентская база»

Статус: `DRAFT`. Основная гранулярность подтверждена; SQL заблокирован до проверки временных границ, source keys, статусов и контрольных значений.

Предлагаемый объект: `mart.client_base_snapshot`.

Гранулярность одной строки:

> уровень охвата × отчётная дата × клуб (только для club scope) × возраст × возрастная группа × пол × стаж × категория посещений.

Уровни охвата:

- `club` — уникальный человек внутри клуба;
- `network` — уникальный человек по всей сети независимо от числа клубов.

Мера строки — количество уникальных людей. Строки разных scope нельзя суммировать между собой.

## Временный source-side набор

Этот набор не хранится на VM-2. Он нужен внутри SQL для дедупликации и расчётов.

| Поле | Источник | Правило | Статус |
|---|---|---|---|
| `report_date` | генерируемый календарь | понедельники UNION первые числа, unique | CONFIRMED |
| `client_id` | `Reference141.ID` / фактически `_Reference141X1._IDRRef` | бинарный идентификатор без PII | CONFIRMED logical / физическое имя проверить |
| `club_id` | `Reference59.Fld687` → `Reference132.ID` | основной клуб доступа | CONFIRMED metadata |
| `active_from` | `Reference59.Fld671`; пакет `max(check.Date_Time, subscription.Fld671)` | включать только `active_from < report_date` | CONFIRMED rule / package source verify |
| `active_to` | `Reference59.Fld672` | включать `active_to >= report_date - 1 day`; пакет использует срок взрослого абонемента | CONFIRMED boundary / package source verify |
| `source_state` | `Reference59.Marked/Fld678/Fld679/Fld695`; `Document346.Marked/Posted/Fld4910`; `AccumRg7575.Active` | исключения только после подтверждения | BLOCKER |
| `birth_date` | `Reference141.Fld1507` | только для расчёта возраста, не переносить | CONFIRMED metadata |
| `gender_ref` | `Reference141.Fld1527` | enum mapping | CONFIRMED metadata / значения проверить |
| `tenure_ref` | `InfoRg5654.Fld5656` | последняя запись клиента на момент снимка | CONFIRMED source / boundary проверить |
| `visit_count_30d` | `AccumRg7575` | посещения клиента во всей сети в `[report_date-30d, report_date)` | CONFIRMED requirement / counting rule проверить |

Перед группировкой:

- для `club` выполнить `DISTINCT (report_date, club_id, client_id)`;
- для `network` выполнить `DISTINCT (report_date, client_id)`.

Атрибуты клиента и network-wide активность должны быть однозначны для этих ключей.

## Целевые колонки `mart.client_base_snapshot`

| Целевая колонка | Бизнес-описание | Источник/преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|
| `scope_level` | `club` или `network` | явная grouping branch | UNKNOWN | нет | CONFIRMED | allowed values |
| `report_date` | Отчётная дата снимка | календарь отчётных дат | `date` | нет | CONFIRMED | понедельник или первое число; unique |
| `club_id` | Стабильный клуб | `Reference132.ID`; NULL для network | UNKNOWN | по scope | CONFIRMED source | required iff club |
| `club_name` | Название клуба | `Reference132.Description`; NULL для network | UNKNOWN | по scope | CONFIRMED source | ID → одно актуальное имя |
| `age_years` | Полных лет на отчётную дату | `report_date`, `Reference141.Fld1507` | `smallint` | UNKNOWN | CONFIRMED rule | дни рождения/29 февраля |
| `age_group` | Дети `<14`, Юниоры `14–17`, Взрослые `18+` | `age_years` | UNKNOWN | UNKNOWN | CONFIRMED current boundaries | 13/14/17/18 |
| `gender` | Пол клиента | `Reference141.Fld1527` → enum | UNKNOWN | да | CONFIRMED source / values pending | enum coverage |
| `membership_tenure` | `New`, `Renew`, `Ex` на дату снимка | latest `InfoRg5654` by client before snapshot | UNKNOWN | UNKNOWN | CONFIRMED categories | as-of control |
| `activity_bucket` | Не ходил; 1; 2–3; 4–7; 8+ | network-wide `visit_count_30d` | UNKNOWN | нет | CONFIRMED | boundary tests |
| `client_count` | Уникальные люди внутри scope/group | count после scope-specific dedupe | `integer`/`bigint` | нет | CONFIRMED | сумма vs distinct source отдельно по scope |

Физические типы ссылок и текстов подтвердить через `pg_catalog` до SQL.

## Сравнительные метрики

| Метрика | Источник для Power BI | Статус |
|---|---|---|
| Размер базы по сети | сумма `client_count` только при `scope_level = network` | CONFIRMED |
| Размер базы по клубам | сумма `client_count` только при `scope_level = club` | CONFIRMED |
| Прирост к Excel-плану | DAX над `client_count` и внешним планом | CONFIRMED boundary |
| Прирост к 1 января | DAX над агрегированными снимками: `(факт - база) / база` | CONFIRMED BY DESIGN |
| Прирост к прошлому году | DAX с подтверждённым mapping сравнительной даты | CONFIRMED concept |
| Активная база, % | категории кроме `Не ходил` / вся база | CONFIRMED concept |
| Retention | отдельная `mart.client_base_retention`; см. `docs/mappings/client_base_retention.md` | CONFIRMED semantics |

## Не переносить на VM-2

- `client_id` и `base_item_id` после source-side агрегации;
- ФИО;
- телефон;
- email;
- имя владельца;
- сырые строки абонементов, пакетов и посещений.

## Подтверждённые metadata-объекты

| Объект 1С | Storage name | Ключевые поля/индексы |
|---|---|---|
| Справочник.Контрагенты | `Reference141` | ID, дата рождения, пол, тип клиента |
| Справочник.Абонементы | `Reference59` | клиент, даты, клуб, стаж; индексы дат/клиента |
| Справочник.Клубы | `Reference132` | ID, name |
| РегистрСведений.ВидСтажаКлиентов | `InfoRg5654` | period, client, tenure; index client+period |
| РегистрНакопления.Посещения | `AccumRg7575` | period, client, club, active, quantity; indexes client+period/club+period |
| Документ.Посещение | `Document325` | posted, marked, operation, client |
| Документ.ЧекККМ | `Document346` | date, posted, marked, status |
| ЧекККМ.ДополнительныеПакеты | `Document346.VT4913` | subscription, client, line key |

Источник metadata: `Структура хранения базы данных.txt`, SHA-256 `9e82c7067596cf9cf1ef8dd890c51914f9af2d9399edd9b994d35c4a48999058`.
