# Source-to-target mapping: агрегированный снимок «Клиентская база»

Статус: `SNAPSHOT/RETENTION DEFERRED / client_base_daily BR-038 IMPLEMENTATION AND RERUN VALIDATED 2026-08-25`.
Граница membership-снимка и необходимость раздельных scope подтверждены.
Этот пакет касается только `mart.client_base_daily`; редкий snapshot, retention
и их дополнительные разрезы остаются отдельными отложенными продуктами.

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

Статус: `INITIAL LOAD COMPLETED — ADR-0031 / 2026-08-19`.

Решение пользователя от 2026-07-29: показатель «% посещений от КБ» обязан
брать знаменатель из витрины клиентской базы, а не из текущей таблицы Power BI
`КБфакт`.

`mart.client_base_snapshot` нельзя использовать напрямую: его отчётные даты —
только понедельники и первые числа месяцев, а показатель посещаемости делит
число посещений на количество выбранных календарных дней. Поэтому предложено
не менять контракт редких снимков, а расширить домен отдельным компактным
дневным набором `mart.client_base_daily`.

### Подтверждённый gap детских пакетов

Read-only review CB-PKG-001—003 2026-08-25 установил, что текущий extract
`mart.client_base_daily` формирует universe только из `Reference59`; ветвь
`Document346.VT4913 → ребёнок` в него не входит. Это противоречит
подтверждённому определению клиентской базы «действующий абонемент **или
детский пакет**», а не отсутствию package-полей в минимальном target grain.

На 2026-08-25 child-package branch добавила бы 15 759 уникальных
`ребёнок × клуб` и 15 714 уникальных детей сети сверх current membership
universe. На всём BR-003 `[2025-01-01, 2027-01-01)` gap существует на каждом
из 730 дней: 5 154 048/5 141 198 package-only client-days для club/network.
Подробные controls и source-state границы: [review 2026-08-25](../reports/client_base_package_coverage_review_2026-08-25.md).

S3-CBD-PKG-001 применяет BR-037 sales/return scope: 399 неположительных sales
rows исключены, 52 строки без physical sales group сохранены. Пользователь
подтвердил BR-038: все valid child packages получают `age_group = «Дети»`
независимо от фактического возраста, который сохраняется в `age_years`.
Package interval вычитается из обычного membership interval до агрегации, чтобы
клиент не задваивался. У факта остаются семь колонок и тот же grain; наличие
`Дети` при возрасте 14+ или неизвестном возрасте контролируется отдельным
independent source reconciliation. Подробности: [решение](../reports/client_base_children_packages_age_contract_decision_2026-08-25.md) и [execution evidence](../reports/client_base_children_packages_execution_2026-08-25.md).

Гранулярность:

> уровень охвата × календарная дата × клуб (только для `club`) × возраст ×
> возрастная группа × пол.

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип | NULL | Статус | Проверка |
|---|---|---|---|---|---|---|
| `scope_level` | `club` или `network` | две явные source-side branches | `text` | нет | CONFIRMED | SV-111, S3-CBD-ADMISSION-001 |
| `report_date` | каждый календарный день целевой истории; снимок на 00:00 | календарь дней вместо понедельников/первых чисел | `date` | нет | CONFIRMED — решение пользователя | BR-005, SV-111 |
| `club_id` | основной клуб доступа; `NULL` только для network | `Reference59.Fld687 → Reference132.ID` после membership dedupe → canonical hex text | `text` | только `network` | CONFIRMED source key | SV-111, S3-CBD-ADMISSION-001 |
| `age_years` | возраст на отчётную дату | `Reference141X1.Fld1507` и `report_date`; sentinel `0001-01-01` → `NULL` | `smallint` | да | CONFIRMED current client-base rule | SV-111 |
| `age_group` | `Дети` для BR-038 package-interval либо возраста `<14`; юниоры `14–17`, взрослые `18+`, `Не указано` | `age_years` и source-kind до агрегации | package получает `Дети` при любом фактическом/неизвестном возрасте; иначе `NULL → «Не указано»`, возраст `<14`, включая отрицательный, → `Дети` | `text` | нет | CONFIRMED BR-038 user decision 2026-08-25 | full-horizon CBD load + independent package-origin control |
| `gender` | пол клиента на отчётную дату либо `Не указано` | `Reference141X1.Fld1527` → two confirmed current codes; other/`NULL` → `Не указано` | `text` | нет | CONFIRMED current rule | SV-111 |
| `client_count` | уникальные действующие клиенты в scope и разрезах | distinct client after BR-005 and scope-specific dedupe | `bigint` | нет | CONFIRMED source formation | SV-111, S3-CBD-ADMISSION-001 |

Отдельные столбцы стажа и активности не включаются: у отчёта посещаемости нет
таких фильтров, а их перенос увеличил бы grain без подтверждённого потребителя.
Наборы `club` и `network` не суммируются. Физический ключ:
`(scope_level, report_date, club_id, age_years, age_group, gender)` с
`NULLS NOT DISTINCT`; он допускает ровно одну network-строку с пустым клубом
и одну строку неизвестного возраста для комбинации разрезов. DAX метрики посещаемости выбирает
`club` при фильтре клуба и `network` без фильтра клуба, затем считает среднее
`client_count` по выбранным дням. Решение пользователя от 2026-07-29 задаёт
общую семантику возрастного фильтра: `visit_count` использует возраст на дату
посещения, `client_count` — возраст на ту же отчётную дату снимка.

| ID | Проверка | Ожидаемый результат | Статус |
|---|---|---|---|
| CBD-V01 | покрытие календаря | ровно один дневной набор для каждого дня целевой истории и обоих scope | VALIDATED source formation — SV-111: 730/730 дней BR-003 в обоих scope; interval-control 7,039 с |
| CBD-V02 | boundary 00:00 | начало в D исключается, окончание D−1 включается согласно BR-005 | VALIDATED — SV-069 и 4 exact anchor checks SV-111 |
| CBD-V03 | ключи/дубли scope | `club` dedupe по `(date, club, client)`, `network` по `(date, client)`; итог не смешивает scope | VALIDATED source formation — SV-111; S3-CBD-ADMISSION-001: 0 invalid scope/club combinations |
| CBD-V04 | возраст | контролируются дни рождения и границы 13/14/17/18; рассчитанный возраст `<14` всегда относится к «Детям» | VALIDATED — SV-111 на 2026-07-01: возрастные границы представлены, sentinel `0001-01-01` даёт `NULL`, отрицательных возрастов нет. Full-horizon load выявил 174 агрегированных строк с отрицательным возрастом; пользователь 2026-08-19 подтвердил их сохранение в «Дети». |
| CBD-V05 | пол | каждое значение enum однозначно отображается или разрешённо остаётся `NULL` | VALIDATED — SV-111 на 2026-07-01: вся cohort покрыта двумя текущими кодами «Женский»/«Мужской», неожиданных non-NULL кодов нет |
| CBD-V06 | сверка знаменателя | среднее дневной КБ воспроизводит согласованный контрольный срез посещаемости | VALIDATED source formation — SV-111: 0 differences at 4 direct current-M anchor dates; end-to-end Power BI reconciliation remains post-load |

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
