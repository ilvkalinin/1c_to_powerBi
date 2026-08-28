# Source-to-target mapping: «Загрузка сотрудников»

Статус: `BUSINESS MAPPING COMPLETE / employee_activity_interval IMPLEMENTED / employee_presence_day STAGE 2 BLOCKED`.

Единственного source grain нет. Отчёт использует общий факт ДПФУ и дневной
план, а для загрузки — самостоятельные события занятий, дежурств, купонов и
присутствия. Одна объединённая таблица исказила бы часы либо выручку.

## Компонент A: кандидат факта активности сотрудника

Целевой проектный объект: `mart.employee_activity_interval`.

Гранулярность до агрегации:

> одно квалифицированное событие занятия, дежурства или купона × сотрудник ×
> клуб × интервал начала/окончания × тип активности.

Логический ключ: `activity_event_key`. ПЗ подтверждён как
`Document329 ID × VT4352 line`, ГЗ — `Document279 ID`, дежурство — hash точной
current-M группы, coupon — hash `(client_code, club_id, activity_id,
employee_id, service_id, class_start)`. Current `Table.Distinct` сокращает
13,584 строк до 13,428; у 149 ключей отличается только visit timestamp, а
день, минуты, договор и IDs совпадают.

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|
| `activity_date` | дата активности | `Document329.Fld4306` / `Document279.Fld3218` / `InfoRg7107.Fld7110` / `Document325.Date_Time` | дата начала; coupon — calendar day qualifying visit | `date` | нет | CONFIRMED current | EW-V01, EW-V03, EW-FOLLOWUP-V03B |
| `club_id` | фактический клуб | `Document329.Fld4310` / `Document279.Fld3224` / `InfoRg7107.Fld7108` | стабильный ID, не название | UNKNOWN | нет | CONFIRMED source | EW-V01 |
| `employee_id` | тренер/дежурный | `Document329.Fld4322` / `Document279.Fld3223` / `InfoRg7107.Fld7109` | ID `Reference225` | UNKNOWN | нет | CONFIRMED source | EW-V01 |
| `activity_id` | направление | услуга → `Reference163.Fld1733 → Reference70`; дежурство — помещение → rule | не подменять помещением | `text` | да | CONFIRMED source / current classification pending for duty | EW-V03 |
| `service_id` | услуга занятия | `Document329.Fld4316` / `Document279.Fld3226` | стабильный ID; `NULL` у дежурства | `text` | да | CONFIRMED source | EW-V02A |
| `room_id` | помещение | `InfoRg7107.Fld7113` / `Document329.Fld4320` / `Document279.Fld3227` | ID `Reference191` | `text` | да | CONFIRMED source | EW-V03C |
| `activity_kind` | тренировка / дежурство / купон 1 / купон 2 | ветка и классификация купона | явная константа | `text` | нет | CONFIRMED business | EW-V02A, EW-V03B, EW-FOLLOWUP-V03B |
| `start_at`, `end_at` | границы интервала | ветка занятия/дежурства | без округления до 15 минут | `timestamp` | нет | CONFIRMED current; 3 invalid GZ rows excluded | EW-V02A |
| `duration_minutes` | длительность | интервалы; купон: `Fld7012 × Fld1767` | coupon formula; `GREATEST(0, raw duty − raw coupon overlap)` для дежурства | `numeric` | нет | CONFIRMED user decision | EW-V03A, EW-FOLLOWUP-V03B, BR-040 |
| `payment_kind` | платно / бесплатно / дежурство | `Reference163.Fld1778`, ветка дежурства | текущая DAX-классификация | `text` | нет | CONFIRMED current / value pending | EW-V02 |

## Компонент B: переиспользуемые факты

| Потребность отчёта | Объект / mapping | Гранулярность | Решение |
|---|---|---|---|
| Выручка, услуги, средний чек, тренер | [факт ДПФУ](dpfu_revenue.md) | движение услуги | `REUSE`; не создавать копию |
| Дневные плановые KPI | компонент плана [ДПФУ](dpfu_revenue.md) | дата × клуб × направление × тренер × клиент | `REUSE`; `COUNT(Клиент)` — current rule до EW-V04 |
| Тренировки ИП | [факт ИП](ip_training.md) | дата × клуб × сотрудник × клиент × услуга | `REUSE` источников; не смешивать с часами |
| Часы пребывания | `Document325` + `Reference225.Fld2504` | сотрудник × день × клуб | `NEW` компактный агрегат-кандидат |
| Порог отчислений | `_СпрСтавки` | внешний файл Power BI | `NOT_APPLICABLE`: не переносить в PostgreSQL по решению пользователя 2026-07-30 |

## Компонент C: `employee_presence_day` — реализация заблокирована

Целевой grain остаётся `employee × presence_date × actual club`. Текущий M
группирует по display-name, однако для возможного PostgreSQL-contract нужны
стабильные IDs. Ни одна из строк ниже не разрешает создание SQL или витрины:
атрибуция полного current-M domain блокирована EPD-V04.

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Статус | Evidence / test |
|---|---|---|---|---|---|---|---|
| `presence_date` | дата присутствия | `AccumRg7575.Period` | `Period::date` из exact current-M path | `date` | нет | CONFIRMED current | EPD-V02 |
| `club_id` | фактический клуб | `AccumRg7575.Fld7577RRef` | стабильный ID, не название клуба | `text` | нет | CONFIRMED source | EPD-V01, EPD-V02 |
| `employee_id` | сотрудник | `Reference225.ID` через `Reference225.Fld2504RRef = AccumRg7575.Fld7576RRef` | допустим только когда у клиента ровно один employee ID; 29,431 visits не имеют связи, 708 имеют две | `text` | нет | BLOCKED | EPD-V04 |
| `presence_minutes` | минуты в клубе | `Document325.Fld4172`, `Document325.Fld4174` | `effective_end - start`; sentinel/open and after-day end клиппируются концом start-day точно как current M | `numeric` | нет | CONFIRMED current formula / target blocked | EPD-V02, EPD-V05 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `InfoRg7006`, `Document329`, `Document279`, `Document313`, `Document329.VT4352`, `Enum448` | занятия, состояние, отмена | CONFIRMED current sources; key/state pending | Power Query и metadata |
| `InfoRg7107`, `Reference191` | дежурства, помещение и минуты | CONFIRMED current sources | Power Query и metadata |
| `Document325`, `AccumRg7575`, `Reference225`, `Reference59` | СКУД и сотрудник-клиент/ИП | BLOCKED for `employee_presence_day`: 29,431 qualified visits lack employee and 708 have two | [EPD Stage 2](../reports/employee_presence_day_stage2_validation_2026-08-28.md) |
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
| CONFIRMED | ключи занятий и `VT4352` | PZ `Document329 × VT line`, GZ `Document279`; current VT multiplicity сохраняется | EW-V02A |
| CONFIRMED user decision | купоны/дежурства | `GREATEST(0, raw duty − raw coupon overlap)`; union не применяется | EW-V03A / BR-040 |
| CONFIRMED | coupon physical row | 149 `Table.Distinct` повторов отличаются лишь visit timestamp; business key, minutes, day, contract и IDs инвариантны | EW-FOLLOWUP-V03B |
| CONFIRMED | `InfoRg6612` | active/unique technical rows | EW-V04 |
| BLOCKED (separate fact) | СКУД сотрудника | Exact current-M domain: 29,431 qualified visits without employee and 708 with two employees; `employee_presence_day` не создаётся. Historical EW-V05 broader visit domain had 1,292 multi-link visits. | EPD-V04 / EW-V05 |
| BLOCKED (not activity source) | кадровые интервалы | 655 nonpositive и 187 overlapping pairs; historical attribution не выдумывается | EW-V07 |
| CONFIRMED | ДПФУ reuse | независимые source totals for 7575/7646 captured | EW-V06 |
| NOT_APPLICABLE | `_СпрСтавки` | внешний файл остаётся в Power BI | EW-V08 не выполняется для PostgreSQL |
| CONFIRMED | история и refresh | история следует BR-003, refresh ежедневно | решение пользователя 2026-07-30 |
