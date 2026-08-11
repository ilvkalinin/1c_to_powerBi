# Source-to-target mapping: «Загрузка сотрудников»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0014 / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-074`.

Единственного source grain нет. Отчёт использует общий факт ДПФУ и дневной
план, а для загрузки — самостоятельные события занятий, дежурств, купонов и
присутствия. Одна объединённая таблица исказила бы часы либо выручку.

## Компонент A: кандидат факта активности сотрудника

Целевой проектный объект: `mart.employee_activity_interval`.

Гранулярность до агрегации:

> одно квалифицированное событие занятия, дежурства или купона × сотрудник ×
> клуб × интервал начала/окончания × тип активности.

Логический ключ: `activity_event_key`; его source composition остаётся
`VALIDATION_PENDING` до EW-V01–EW-V03.

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `activity_date` | дата начала | `Document329.Fld4306` / `Document279.Fld3218` / `InfoRg7107.Fld7110` | дата начала ветки | `date` | нет | CONFIRMED current | EW-V01, EW-V03 |
| `club_id` | фактический клуб | `Document329.Fld4310` / `Document279.Fld3224` / `InfoRg7107.Fld7108` | стабильный ID, не название | UNKNOWN | нет | CONFIRMED source | EW-V01 |
| `employee_id` | тренер/дежурный | `Document329.Fld4322` / `Document279.Fld3223` / `InfoRg7107.Fld7109` | ID `Reference225` | UNKNOWN | нет | CONFIRMED source | EW-V01 |
| `activity_id` | направление | услуга → `Reference163.Fld1733 → Reference70`; дежурство — помещение → rule | не подменять помещением | UNKNOWN | да | CONFIRMED need / pending | EW-V03 |
| `service_id` | услуга занятия | `InfoRg7006.Fld7010` / `Document329.Fld4316` / `Document279.Fld3226` | стабильный ID; `NULL` у дежурства | UNKNOWN | да | CONFIRMED source | EW-V01 |
| `room_id` | помещение | `InfoRg7107.Fld7113` / `Document329.Fld4320` / `Document279.Fld3227` | ID `Reference191` | UNKNOWN | да | CONFIRMED source | EW-V03 |
| `activity_kind` | тренировка / дежурство / купон 1 / купон 2 | ветка и классификация купона | явная константа | `text` | нет | CONFIRMED business | EW-V02 |
| `start_at`, `end_at` | границы интервала | ветка занятия/дежурства | без округления до 15 минут | `timestamp` UNKNOWN | нет | CONFIRMED current | EW-V01 |
| `duration_minutes` | длительность | интервалы; купон: `Fld7012 × Fld1767` | разность интервала / текущая формула купона | `numeric` | нет | CONFIRMED current | EW-V03 |
| `payment_kind` | платно / бесплатно / дежурство | `Reference163.Fld1778`, ветка дежурства | текущая DAX-классификация | `text` | нет | CONFIRMED current / value pending | EW-V02 |

## Компонент B: переиспользуемые факты

| Потребность отчёта | Объект / mapping | Гранулярность | Решение |
|---|---|---|---|
| Выручка, услуги, средний чек, тренер | [факт ДПФУ](dpfu_revenue.md) | движение услуги | `REUSE`; не создавать копию |
| Дневные плановые KPI | компонент плана [ДПФУ](dpfu_revenue.md) | дата × клуб × направление × тренер × клиент | `REUSE`; `COUNT(Клиент)` — current rule до EW-V04 |
| Тренировки ИП | [факт ИП](ip_training.md) | дата × клуб × сотрудник × клиент × услуга | `REUSE` источников; не смешивать с часами |
| Часы пребывания | `Document325` + `Reference225.Fld2504` | сотрудник × день × клуб | `NEW` компактный агрегат-кандидат |
| Порог отчислений | `_СпрСтавки` | внешний файл Power BI | `NOT_APPLICABLE`: не переносить в PostgreSQL по решению пользователя 2026-07-30 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `InfoRg7006`, `Document329`, `Document279`, `Document313`, `Document329.VT4352`, `Enum448` | занятия, состояние, отмена | CONFIRMED current sources; key/state pending | Power Query и metadata |
| `InfoRg7107`, `Reference191` | дежурства, помещение и минуты | CONFIRMED current sources | Power Query и metadata |
| `Document325`, `AccumRg7575`, `Reference225`, `Reference59` | СКУД и сотрудник-клиент/ИП | CONFIRMED sources; cardinality pending | Power Query и metadata |
| `AccumRg7575`, `AccumRg7646`, `Reference163`, `Reference70`, `Reference132`, `Reference141X1` | услуги и выручка | CONFIRMED reuse sources | mapping ДПФУ |
| `InfoRg6612`, `Reference217`, `Reference183` | дневной план | CONFIRMED current sources; key/active pending | Power Query и metadata |
| `InfoRg6291`, `Reference101` | должность и ранг | CONFIRMED current sources; interval pending | Power Query и metadata |
| `_СпрСтавки` | месячный порог выручки | EXTERNAL / Power BI | остаётся внешним файлом по решению пользователя 2026-07-30 |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники | ДПФУ, план, занятия, табель, сотрудники, клубы каталогизированы; `Reference191` добавлен как новый потребитель | CONFIRMED |
| Проверенные продукты | общий факт ДПФУ, дневной план и факт ИП соответствуют независимым потребителям | CONFIRMED |
| Проверенные правила | BR-001, BR-002, BR-003, BR-004, BR-009, BR-010, BR-013 применимы; история по BR-003 и ежедневный refresh подтверждены пользователем 2026-07-30 | CONFIRMED |
| Сравнение grain и ключей | движение услуги, назначение, интервал и СКУД имеют несовместимые ключи | CONFIRMED |
| Сравнение семантики | выручка/план — KPI; интервалы — загрузка; СКУД — знаменатель; порог — зарплатный норматив | CONFIRMED |
| Решение | `REUSE` ДПФУ/план/ИП; `NEW` `mart.employee_activity_interval` и `mart.employee_presence_day`; пороги остаются во внешнем Power BI-файле | DESIGNED — ADR-0014 |
| Причина | объединение интервалов с движениями исказит суммы и часы | CONFIRMED reasoning |

## Риски и проверки

| Статус | Элемент | Риск / причина | Проверка |
|---|---|---|---|
| VALIDATION_PENDING | ключи занятий и `VT4352` | one-to-many раздует минуты | EW-V01, EW-V02; `NOT_EXECUTED — ожидается подключение к корпоративной сети` |
| VALIDATION_PENDING | купоны/дежурства | двойное вычитание, отрицательные часы | EW-V03; `NOT_EXECUTED — ожидается подключение к корпоративной сети` |
| VALIDATION_PENDING | `InfoRg6612` | inactive/дубли изменят план | EW-V04; `NOT_EXECUTED — ожидается подключение к корпоративной сети` |
| VALIDATION_PENDING | СКУД сотрудника | связь может быть many-to-many | EW-V05; `NOT_EXECUTED — ожидается подключение к корпоративной сети` |
| VALIDATION_PENDING | ДПФУ и кадровые интервалы | суммы, статусы, историческая должность | EW-V06, EW-V07; `NOT_EXECUTED — ожидается подключение к корпоративной сети` |
| NOT_APPLICABLE | `_СпрСтавки` | внешний файл остаётся в Power BI | EW-V08 не выполняется для PostgreSQL |
| CONFIRMED | история и refresh | история следует BR-003, refresh ежедневно | решение пользователя 2026-07-30 |
