# Source-to-target mapping: «KPI Фитнеса»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0012 / TECHNICAL VALIDATION COMPLETE`.
Реализация и DDL не создавались. Выполненные read-only проверки зафиксированы
в SV-054—SV-061.

## Компонент A: факт платных фитнес-услуг

Гранулярность одной строки:

> дата движения × фактический клуб × клиент × тренер × услуга × подразделение × формат × категория расчёта.

Ключ: `(source_register, recorder_id, line_no)` до группировки;
уникальность — `VALIDATED` в SV-054. Общая выручка, количество и средний чек
имеют разные подтверждённые фильтры ИП/аренды и должны быть отдельными
DAX-мерами над классифицированным фактом.

| Целевая колонка | Бизнес-описание | Исходник / преобразование | Тип | NULL | Статус / доказательство | Тест |
|---|---|---|---|---|---|---|
| `service_date` | дата учёта услуги | `AccumRg7575.Period` / `AccumRg7646.Period` → `date` | `date` | нет | CONFIRMED current SQL | KF-V03 |
| `club_id`, `club_name` | фактический клуб | `Fld7577`/`Fld7653` → `Reference132` | UNKNOWN, `text` | нет | CONFIRMED current SQL | KF-V02 |
| `client_key` | стабильный скрытый ключ для УЧК и Renew | `Fld7576`/`Fld7648` → защищённый ключ | UNKNOWN | нет | CONFIRMED need | KF-V02 |
| `client_code` | код клиента в «Дневном плане до клиента» | `Reference141X1.Code` | `text` | нет | CONFIRMED report requirement and access policy BR-017 | KF-V02; permissions/RLS |
| `employee_id`, `employee_name` | тренер для KPI/Renew/плана | `Fld7582`/`Fld7652` → `Reference225` | UNKNOWN, `text` | да | CONFIRMED current SQL | KF-V02 |
| `service_id`, `service_name` | услуга | `Fld7579`/`Fld7649` → `Reference163` | UNKNOWN, `text` | нет | CONFIRMED current SQL | KF-V02 |
| `activity_id`, `activity_name` | подразделение | `Reference163.Fld1733` → `Reference70` | UNKNOWN, `text` | нет | CONFIRMED current SQL | KF-V02 |
| `training_format_name` | формат тренировки | `Reference163.Fld1803` → `Reference248`; `Платный урок → Групповое занятие` | `text` | да | CONFIRMED current M | KF-V02 |
| `calculation_category` | аренда / прочая услуга / ИП | утверждённая текущая классификация | `text` | нет | CONFIRMED current M/DAX | KF-V08 |
| `age_category` | дети / юниоры / взрослые на дату | `Reference141X1.Fld1507` и границы BR-008 | `text` | да | CONFIRMED user rule | KF-V08 |
| `service_quantity` | количество со знаком | `SUM(Fld7585)` / `SUM(Fld7657)` | `numeric` | нет | CONFIRMED user rule | KF-V01–04 |
| `revenue_amount` | выручка со знаком | `SUM(Fld7586)` / `SUM(Fld7659)` | `numeric` | нет | CONFIRMED user rule | KF-V01–04 |

`service_group` для «Худей/качай» остаётся классификацией внешнего Excel
внутри Power BI и не входит в PostgreSQL-факт: `CONFIRMED — решение
пользователя 2026-07-30`.

## Компонент B: тренировки и выручка ИП

`REUSE` [факта тренировок ИП](ip_training.md): количество ИП, тренер, клуб,
клиент и услуга. Не создавать копию `InfoRg7006`. Его grain несовместим с
движением выручки, поэтому общая выручка ИП остаётся отдельной ветвью
`AccumRg7370`: `revenue_date`, `club_id`, `service_id`, `revenue_amount`.
Дата — день оплаты, не месяц; filter `RecordKind` и связь с услугой —
`VALIDATED` для текущей денежной ветви (SV-055, SV-061). Для ПЗ ИП первый
релиз сохраняет наблюдаемую кратность PBIT: 49 200 строк из 48 973 физических
событий (SV-058, BR-018); уникальные события — отдельное улучшение методики.

## Компонент C: текущий план

Гранулярность:

> дата плана × клуб × подразделение × тренер × плановый клиент.

| Целевая колонка | Исходник / преобразование | Тип | NULL | Статус | Тест |
|---|---|---|---|---|---|
| `plan_date` | `InfoRg6612.Fld6613::date` | `date` | нет | CONFIRMED current M | KF-V06 |
| `club_id`, `activity_id`, `employee_id` | `Fld6615`, `Fld6614`, `Fld6616` и справочники | UNKNOWN | нет | CONFIRMED current M | KF-V06 |
| `planned_client_key`, `planned_client_code` | `Fld6617` → `Reference141X1` | UNKNOWN, `text` | нет | CONFIRMED detailed page and access policy BR-017 | KF-V06; permissions/RLS |
| `planned_revenue` | `Fld6620` | `numeric` | нет | CONFIRMED current DAX | KF-V06 |

Количество из `COUNT(Fld6619)` не входит в целевой контракт: текущие меры
используют из дневного плана только выручку. `Active` и ключ строки —
`VALIDATION_PENDING`.

## Компонент D: внешние планы и знаменатель вовлечённости

Годовой бюджет — Excel, план мероприятий — Google Sheets, классификатор услуг
— Excel. Все три источника остаются в Power BI и не должны неявно попадать в
SQL-факт: `CONFIRMED — решение пользователя 2026-07-30`. Для вовлечённости требуется `EXTEND` существующего
`mart.client_base_daily`; совместимость grain, club/network scope и периода —
`VALIDATION_PENDING`.

## Подтверждённые источники

| Объект | Роль | Статус / доказательство |
|---|---|---|
| `AccumRg7575`, `AccumRg7646` | движения услуг и выручки | CONFIRMED current SQL |
| `AccumRg7370` | оплаты ИП | CONFIRMED current SQL |
| `InfoRg7006`, `Document329`, `Document279` | тренировки ИП | CONFIRMED current SQL / reuse `ip_training` |
| `InfoRg6612` | дневной план | CONFIRMED current M |
| `Reference132`, `141X1`, `163`, `70`, `225`, `248`, `217` | измерения факта/плана | CONFIRMED current M/SQL |
| годовой бюджет (Excel) / план мероприятий (Google Sheets) / классификатор услуг (Excel) | план и структура | EXTERNAL / остаются в Power BI — решение пользователя 2026-07-30 |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Источники из каталога | все технические объекты уже каталогизированы | CONFIRMED |
| Продукты из каталога | факт ДПФУ, тренировки ИП, дневной план ДПФУ, `mart.client_base_daily` | CONFIRMED |
| Общие правила | BR-001, BR-002, BR-003, BR-004, BR-007, BR-008, BR-009, BR-010, BR-013, BR-018 | CONFIRMED / BR-004, BR-010, BR-013 implementation pending |
| Grain и ключи | KPI требует тренера и клиента; текущий факт ДПФУ уже имеет client-level источник, но employee — подтверждённый новый потребитель | CONFIRMED consumer / technical key pending |
| Семантика | ДПФУ совпадает с отчётом «Выручка ДПФУ»; ИП — с «Отчётом по ИП»; планы имеют отдельный grain | CONFIRMED |
| Решение | `EXTEND` логического факта ДПФУ полями сотрудника и кода клиента; `REUSE` тренировки ИП и client-base daily; `NEW` не требуется | PROPOSED / technical validation required |
| Затронутые потребители | Выручка ДПФУ, Записи администраторов, Выручка рецепции, Отчёт по ИП, Работа с посещаемостью | CONFIRMED |

## Риски и валидация

| ID | Статус | Проверка / ожидаемый результат |
|---|---|---|
| KF-V01 | VALIDATED | `(Recorder, LineNo)` уникален в каждом регистре (SV-054). |
| KF-V02 | VALIDATED | source joins покрыты; nullable display-поля не меняют суммы (SV-054). |
| KF-V03 | VALIDATED | active, возвраты и `RecordKind` согласованы с текущими ветвями (SV-054, SV-055). |
| KF-V04 | VALIDATED | две ветви не имеют точных совпадающих бизнес-пар (SV-054). |
| KF-V05 | VALIDATED | тренировки ИП: физическая кратность ПЗ подтверждена; legacy-кратность сохранена по BR-018 (SV-058). |
| KF-V06 | VALIDATED | дневной план: ключ, active, период и `Fld6620` подтверждены (SV-056). |
| KF-V07 | NOT_APPLICABLE для PostgreSQL | годовой бюджет, план мероприятий и классификатор услуг остаются внешними источниками Power BI. |
| KF-V08 | VALIDATED | регулярность и граница истории Renew сохраняют PBIT; улучшения помечены отдельно (SV-060, BR-018). |

Исполненные SQL и результаты — в
[`server_validation_2026-08-05.md`](../source_metadata/server_validation_2026-08-05.md),
SV-054—SV-061.
