# Source-to-target mapping: агрегированный снимок «Клиентская база»

Статус: `DRAFT / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED — SV-069, SV-111`.
Граница membership-снимка и необходимость раздельных scope подтверждены;
реализация и остальные source-side проверки остаются отложенными.

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
| `source_state` | `Reference59.Marked/Fld678/Fld679/Fld695`; `Document346.Marked/Posted/Fld4910`; `AccumRg7575.Active` | исключения только после подтверждения; на control-date `Reference59.Marked = 0` | PARTIALLY VALIDATED — SV-069 |
| `birth_date` | `Reference141.Fld1507` | только для расчёта возраста, не переносить | CONFIRMED metadata |
| `gender_ref` | `Reference141.Fld1527` | enum mapping | CONFIRMED metadata / значения проверить |
| `tenure_ref` | `InfoRg5654.Fld5656` | последняя запись клиента на момент снимка | CONFIRMED source / boundary проверить |
| `visit_count_30d` | `AccumRg7575` | посещения клиента во всей сети в `[report_date-30d, report_date)` | CONFIRMED requirement / counting rule проверить |

Перед группировкой:

- для `club` выполнить `DISTINCT (report_date, club_id, client_id)`;
- для `network` выполнить `DISTINCT (report_date, client_id)`.

`SV-069` подтвердил необходимость обеих ветвей: на 2026-07-01 52 клиента
состоят более чем в одном клубе, а 1 308 сочетаний `клиент × клуб` имеют
несколько active-membership строк. На той же дате получены 81 022 исходные
membership-строки, 79 710 уникальных `клиент × клуб` и 79 658 уникальных
клиентов сети; строк с `Marked = true` в этой cohort нет. Граница BR-005
проверена отдельно: `active_from = D` исключается, `active_to = D - 1`
включается.

Атрибуты клиента и network-wide активность должны быть однозначны для этих ключей.

## Целевые колонки `mart.client_base_snapshot`

| Целевая колонка | Бизнес-описание | Источник/преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|
| `scope_level` | `club` или `network` | явная grouping branch | UNKNOWN | нет | CONFIRMED | allowed values |
| `report_date` | Отчётная дата снимка | календарь отчётных дат | `date` | нет | CONFIRMED | понедельник или первое число; unique |
| `club_id` | Стабильный клуб | `Reference132.ID`; NULL для network | UNKNOWN | по scope | CONFIRMED source | required iff club |
| `club_name` | Название клуба | `Reference132.Description`; NULL для network | UNKNOWN | по scope | CONFIRMED source | ID → одно актуальное имя |
| `age_years` | Полных лет на отчётную дату | `report_date`, `Reference141.Fld1507` | `smallint` | UNKNOWN | CONFIRMED rule | дни рождения/29 февраля |
| `age_group` | Дети `<14`, Юниоры `14–17`, Взрослые `18+`, `Не указано` | `age_years` | `NULL age_years → «Не указано»` | text | нет | CONFIRMED user decision 2026-07-30 | 13/14/17/18, NULL |
| `gender` | Пол клиента либо `Не указано` | `Reference141.Fld1527` → enum | `NULL → «Не указано»`; нераспознанный enum требует технической валидации | text | нет | CONFIRMED user decision 2026-07-30 | enum coverage, NULL |
| `membership_tenure` | `New`, `Renew`, `Ex` либо `Не указано` на дату снимка | latest `InfoRg5654` by client before snapshot | `NULL` результата latest-as-of → `Не указано`; нераспознанный GUID требует технической валидации | text | нет | CONFIRMED user decision 2026-07-30 | as-of control, NULL |
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

## Дневное расширение для «Работы с посещаемостью»

Статус: `CONFIRMED dependency / ARCHITECTURE DESIGNED — ADR-0012/0022 /
TECHNICAL VALIDATION DEFERRED`.

Решение пользователя от 2026-07-29: показатель «% посещений от КБ» обязан
брать знаменатель из витрины клиентской базы, а не из текущей таблицы Power BI
`КБфакт`.

`mart.client_base_snapshot` нельзя использовать напрямую: его отчётные даты —
только понедельники и первые числа месяцев, а показатель посещаемости делит
число посещений на количество выбранных календарных дней. Поэтому предложено
не менять контракт редких снимков, а расширить домен отдельным компактным
дневным набором `mart.client_base_daily`.

Гранулярность:

> уровень охвата × календарная дата × клуб (только для `club`) × возраст ×
> возрастная группа × пол.

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип | NULL | Статус | Проверка |
|---|---|---|---|---|---|---|
| `scope_level` | `club` или `network` | те же source-side branches, что и у snapshot | `text` | нет | CONFIRMED by reuse | CBD-V01 |
| `report_date` | каждый календарный день целевой истории; снимок на 00:00 | календарь дней вместо понедельников/первых чисел | `date` | нет | CONFIRMED — решение пользователя | CBD-V01, CBD-V02 |
| `club_id` | основной клуб доступа; `NULL` для network | `Reference59.Fld687 → Reference132.ID` после membership dedupe | UNKNOWN | только `network` | CONFIRMED by reuse | CBD-V03 |
| `age_years` | возраст на отчётную дату | `Reference141.Fld1507` и `report_date` | `smallint` | по правилу КБ | CONFIRMED by reuse | CBD-V04 |
| `age_group` | дети `<14`, юниоры `14–17`, взрослые `18+`, `Не указано` | `age_years` | `NULL age_years → «Не указано»` | `text` | нет | CONFIRMED by reuse / user decision 2026-07-30 | CBD-V04 |
| `gender` | пол клиента на отчётную дату либо `Не указано` | `Reference141.Fld1527` → enum | `NULL → «Не указано»`; нераспознанный enum требует технической валидации | `text` | нет | CONFIRMED by reuse / user decision 2026-07-30 | CBD-V05 |
| `client_count` | уникальные действующие клиенты в scope и разрезах | тот же membership interval и scope-specific dedupe, что у `mart.client_base_snapshot` | `integer`/`bigint` | нет | CONFIRMED dependency / technical state pending | CBD-V03, CBD-V06 |

Отдельные столбцы стажа и активности не включаются: у отчёта посещаемости нет
таких фильтров, а их перенос увеличил бы grain без подтверждённого потребителя.
Наборы `club` и `network` не суммируются. DAX метрики посещаемости выбирает
`club` при фильтре клуба и `network` без фильтра клуба, затем считает среднее
`client_count` по выбранным дням. Решение пользователя от 2026-07-29 задаёт
общую семантику возрастного фильтра: `visit_count` использует возраст на дату
посещения, `client_count` — возраст на ту же отчётную дату снимка.

| ID | Проверка | Ожидаемый результат | Статус |
|---|---|---|---|
| CBD-V01 | покрытие календаря | ровно один дневной набор для каждого дня целевой истории и обоих scope | PARTIALLY VALIDATED — SV-111: source-side cohort сформирована для всех 28 последовательных дней 2026-07-01—28 и обоих scope за 17,89 с; весь период и физический объект не проверялись |
| CBD-V02 | boundary 00:00 | начало в D исключается, окончание D−1 включается согласно BR-005 | PARTIALLY VALIDATED — SV-069 подтверждает общее membership-правило на 2026-07-01; дневной набор не выполнялся |
| CBD-V03 | ключи/дубли scope | `club` dedupe по `(date, club, client)`, `network` по `(date, client)`; итог не смешивает scope | PARTIALLY VALIDATED — SV-069 подтверждает общее membership-правило на 2026-07-01; дневной набор не выполнялся |
| CBD-V04 | возраст | контролируются дни рождения и границы 13/14/17/18 | VALIDATED — SV-111 на 2026-07-01: возрастные границы представлены, sentinel `0001-01-01` даёт `NULL`, отрицательных возрастов нет |
| CBD-V05 | пол | каждое значение enum однозначно отображается или разрешённо остаётся `NULL` | VALIDATED — SV-111 на 2026-07-01: вся cohort покрыта двумя текущими кодами «Женский»/«Мужской», неожиданных non-NULL кодов нет |
| CBD-V06 | сверка знаменателя | среднее дневной КБ воспроизводит согласованный контрольный срез посещаемости | VALIDATION_PENDING — NOT_EXECUTED — ожидается подключение к корпоративной сети |

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
