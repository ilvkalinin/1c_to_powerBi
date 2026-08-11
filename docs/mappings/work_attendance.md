# Source-to-target mapping: «Работа с посещаемостью»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0022 / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED`.

Целевой проектный объект: `mart.club_attendance_hourly`. Тип — компактная
физическая таблица по ADR-0022; реализация отложена. Production SQL не создаётся.

Гранулярность одной строки:

> дата посещения × фактический клуб × час начала × час окончания (включая
> `NULL`) × пол клиента × возраст клиента на дату посещения.

Логический ключ: состав полей grain; `UNKNOWN` до WA-V01/WA-V07. Это ключ
агрегата, не ключ исходного события.

Пакетный audit 2026-08-11 подтвердил соответствие mapping полному M/DAX,
requirements и ADR-0022. Reuse-граница остаётся прежней: календарь, клубы и
источники посещений переиспользуются, но `mart.visit_client_day` и
`mart.club_day_metrics` не расширяются из-за несовместимой гранулярности.
Следовательно, решение — `DESIGNED — ADR-0022`: отдельный компактный
`mart.club_attendance_hourly`; source states и контрольный grain подтверждены
SV-065/SV-067. Sentinel-дата рождения `0001-01-01 00:00:00` теперь имеет
явное правило BR-019: возраст и возрастная группа остаются `NULL`.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица | Исходная колонка | Преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|---|---|
| `visit_date` | день посещения | `AccumRg7575` | `Period` | `Period::date` | `date` | нет | CONFIRMED current calculation | WA-V05 |
| `club_id` | фактический клуб входа | `AccumRg7575` / `Reference132` | `Fld7577` / `ID` | current query uses `Fld7577`; сопоставить с `Document325.Fld4167` | UNKNOWN | нет | CONFIRMED current source / precedence pending | WA-V01, WA-V05 |
| `start_hour` | час прихода, 0–23 | `Document325` | `Fld4172` | `EXTRACT(hour ...)` | `smallint` | нет | CONFIRMED | WA-V03 |
| `end_hour` | час ухода | `Document325` | `Fld4174` | `EXTRACT(hour ...)`; сохранить `NULL` как отдельное значение current query | `smallint` | да | CONFIRMED current calculation | WA-V03, WA-V07 |
| `sex_code` | пол клиента | `Reference141X1` | `Fld1527` | текущий GUID mapping в Женский/Мужской/`NULL`; постоянный ключ пола подтвердить | `text`/UNKNOWN | да | CONFIRMED current calculation / technical mapping pending | WA-V05 |
| `age_years` | возраст в полных годах на дату посещения | `Document325`, `Reference141X1` | `Fld4172`, `Fld1507` | `CASE WHEN birth_date::date = DATE '0001-01-01' THEN NULL ELSE EXTRACT(year FROM age(visit_date, birth_date)) END` | `smallint` | да | CONFIRMED — BR-019 / решение пользователя 2026-08-11 | WA-V04 |
| `visit_count` | число текущих посещений | `Document325` после связи с `AccumRg7575` | `ID` | `COUNT(Document325.ID)` в текущем grain | `bigint` | нет | CONFIRMED current calculation / source cardinality validated | WA-V01, WA-V05 |
| `club_minutes_total` | суммарные минуты в клубе | `Document325` | `Fld4172`, `Fld4174` | разность окончания и начала в минутах; при `NULL`/минимальном окончании подставлять `23:59:59` даты начала, как в текущем Power Query | `numeric` | нет | CONFIRMED — пользовательское решение 2026-07-31 | WA-V03, WA-V05 |

Не включены в этот кандидат: исходный ID/код/ФИО клиента, ссылки документов,
дата рождения, описание абонемента и сырые GUID. Возраст и пол остаются только
потому, что они являются подтверждёнными срезами визуалов.

## Производные правила Power BI

| Показатель | Правило | Граница PostgreSQL / Power BI | Статус |
|---|---|---|---|
| Всего посещений | `SUM(visit_count)` | готовое число хранится в кандидате; суммирование — DAX | CONFIRMED |
| Среднее время | `SUM(club_minutes_total) / SUM(visit_count)` | DAX | CONFIRMED |
| ПГ | применение календаря `SAMEPERIODLASTYEAR` | DAX | CONFIRMED |
| Утро/день/вечер, час и возрастная группа | детерминированные группы по сохранённым `start_hour`, возрасту на дату посещения | DAX/справочник, без повторного обращения к 1С | CONFIRMED |
| Процент от КБ | `SUM(visit_count) / COUNTD(visit_date) / AVG(дневная КБ)` | DAX над `mart.client_base_daily`; при выбранном клубе — scope `club`, без фильтра клуба — scope `network`; возраст на дате посещения/снимка совпадает | CONFIRMED — решение пользователя 2026-07-29 |
| Загрузка шкафчиков и >80% | почасовое посещение / ёмкость шкафчиков | DAX с внешними Excel-наборами Power BI; в PostgreSQL не переносить | CONFIRMED — решение пользователя 2026-07-30 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `AccumRg7575` | дата/клуб и регистратор движения посещения | CONFIRMED source | M и source metadata |
| `Document325` | операция, клиент, время начала/окончания, документ посещения | CONFIRMED source | M и source metadata |
| `Reference132` | наименование клуба и исключение ДРЦ/УК | CONFIRMED current source | M |
| `Reference141X1` | дата рождения, пол, тип клиента | CONFIRMED source | M и source metadata |
| `Reference59` | текстовое исключение ИП/сотрудников текущего M; дата активации больше не используется для возраста | CONFIRMED current source / target age excluded | M и решение пользователя 2026-07-29 |
| `mart.client_base_daily` | дневная клиентская база — знаменатель рейтинга посещений | CONFIRMED target dependency | решение пользователя 2026-07-29; [mapping КБ](client_base.md) |
| `Шкафчики`, `Макс загрузка`, `Хар-ка клубов`, `МинутыПлан` | ёмкость и мощность | EXTERNAL / Excel остаются в Power BI | решение пользователя 2026-07-30 |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `docs/catalogs/source_objects.md` | `AccumRg7575`, `Document325`, `Reference132`, `Reference141X1`, `Reference59` уже каталогизированы | CONFIRMED |
| Проверенные продукты из `docs/catalogs/data_products.md` | `mart.visit_client_day`, `mart.club_day_metrics`, `mart.client_base_snapshot` | CONFIRMED |
| Проверенные правила из `docs/catalogs/business_rules.md` | BR-001, BR-002, BR-003, BR-004, BR-013 применимы; BR-006 только как current source-precedence validation | CONFIRMED |
| Сравнение гранулярности | client-day теряет число отдельных входов, часы и длительность; club-day теряет часы, пол, возраст; client-base snapshot имеет иной предмет | CONFIRMED |
| Сравнение ключей | существующие ключи `(date, club, client)` и `(date, club)` не воспроизводят кандидатный агрегат | CONFIRMED |
| Сравнение бизнес-семантики | общий источник посещений совпадает, но этот отчёт управляет длительностью и загрузкой, а не distinct клиентами/ГП | CONFIRMED |
| Решение | `NEW` компактный агрегат; переиспользовать источники, календарь и справочник клубов | DESIGNED — ADR-0022; техническая валидация отложена |
| Причина решения | расширение `visit_client_day` изменило бы grain и не сохранило бы кратность входов; отдельная реплика сырых документов запрещена BR-001 | CONFIRMED reasoning |
| Затронутые существующие потребители | новых полей не добавляется в `mart.visit_client_day` и `mart.club_day_metrics`; общий справочник клубов/календарь — REUSE | CONFIRMED |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| VALIDATION_PENDING | `mart.client_base_daily` | подтвердить ежедневное покрытие, выбор `club/network`, совместимость календаря и измерений с метрикой посещений | WA-V06 |
| CONFIRMED | возрастной срез `% посещений от КБ` | sentinel `0001-01-01 00:00:00` преобразуется в `NULL`; возрастная группа остаётся пустой, а не `85+` | BR-019, решение пользователя 2026-08-11; WA-V04 / SV-065 |
| NOT_APPLICABLE | `Шкафчики` и мощности | Excel-наборы остаются в Power BI | WA-V06 не выполняется для PostgreSQL |
| CONFIRMED | состояния документов/регистра | на текущей M-когорте 2026-01—07 нет неактивных, непроведённых или помеченных строк | SV-065; не добавлять новый source-filter |
| CONFIRMED | ключ события и кратность join | на текущей M-когорте 2026-01—07 `COUNT(Document325.ID)` не размножается после регистра | SV-065 |
| CONFIRMED | незакрытый вход | для длительности сохраняется fallback Power Query `23:59:59`; `end_hour` не переписывается, поэтому DAX-флаг остаётся отдельной current-логикой | решение пользователя 2026-07-31; WA-V03 проверяет только физические значения и воспроизводимость |
| CONFIRMED | целевая история, refresh и SLA | история следует BR-003; refresh ежедневно, данные доступны до 08:30 по Москве | решение пользователя 2026-07-30; BR-014 |
