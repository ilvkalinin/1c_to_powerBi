# Source-to-target mapping: «Титульный лист»

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0024 / TECHNICAL VALIDATION DEFERRED`.

Это mapping семантического отчёта, а не проект нового mart. Одна физическая
строка не может одновременно представлять выручку, расход, снимок КБ и
часовой интервал посещения. PostgreSQL SQL/DDL не создаются.

История следует BR-003; отчёт обновляется раз в неделю и доступен до 08:30
по Москве в день обновления (`CONFIRMED — решение пользователя 2026-07-30`,
BR-014).

## Логические наборы и grain

| Набор | Гранулярность одной строки | Логический ключ | Решение |
|---|---|---|---|
| Доходная компонента | дата факта × клуб × статья | `(revenue_date, club_id, revenue_article_code)` | REUSE `mart.revenue_group_summary_daily`; ключ validation pending |
| КБ на выбранную дату | дата × клуб × срезы КБ | grain `mart.client_base_daily` | REUSE / EXTEND consumer; объект ещё не реализован |
| Часовой интервал посещения | дата × фактический клуб × час входа × час выхода × пол × возраст | candidate из `work_attendance` | REUSE / EXTEND consumer; ключ pending |
| Внешние свойства/расходы | внешний файл Power BI | внешний файл Power BI | NOT_APPLICABLE: остаётся в Power BI по решению пользователя 2026-07-30 |
| Renew | строка текущей внешней выгрузки Renew | внешний файл Power BI | REUSE existing Power BI source; `mart.contract_usage` — только обогащение |

## Целевые поля и показатели

| Целевая колонка / мера | Бизнес-описание | Источник и преобразование | Тип | NULL | Grain | Статус | Доказательство | Проверка |
|---|---|---|---|---|---|---|---|---|
| `report_date` | выбранная дата | общий календарь Power BI | `date` | нет | контекст отчёта | CONFIRMED need | описание/DAX | один выбор, coverage Date |
| `club_id` | устойчивый выбранный клуб | общий справочник клубов; не имя из M | `UNKNOWN` | нет | все наборы | CONFIRMED need / type pending | catalogs | unique/orphan |
| `revenue_date` | дата движения выручки | `mart.revenue_group_summary_daily.revenue_date` | `date` | нет | день×клуб×статья | CONFIRMED reuse | mapping `revenue_group_summary` | TS-V01–TS-V03 |
| `revenue_article_code` | членство, штатная DPFU, аренда ИП, рецепция | статьи `02`–`05` общего факта; текущая DPFU TS включает 03+04 | `text` | нет | то же | CONFIRMED current composition / final category validation pending | M/DAX + revenue mapping | category coverage/anti-overlap |
| `revenue_amount` | знаковая выручка компоненты | `mart.revenue_group_summary_daily.revenue_amount` | `numeric` | нет | то же | CONFIRMED reuse | revenue mapping | branch reconciliation |
| `total_revenue_previous_month` | членство + фитнес + рецепция за месяц перед `report_date` | DAX над `revenue_amount`; не физическая колонка | `numeric` | да | фильтр-контекст | CONFIRMED | supplied DAX | month boundary |
| `fitness_share` | фитнес / общая выручка | DAX `DIVIDE` над теми же компонентами | `numeric` | да | фильтр-контекст | CONFIRMED | supplied DAX | zero/NULL denominator |
| `revenue_per_sqm` | общая выручка / площадь | DAX `DIVIDE(total_revenue, club_area_sqm)` | `numeric` | да | фильтр-контекст | CONFIRMED formula / external area stays in Power BI | supplied DAX | Power BI source |
| `club_area_sqm`, `gym_area_sqm`, `group_area_sqm`, `pool_lanes`, `has_children_pool` | физические свойства клуба | внешний файл Power BI | `numeric` / `integer` / `boolean` | UNKNOWN | свойство клуба (период действия UNKNOWN) | EXTERNAL / остаются в Power BI | решение пользователя 2026-07-30 | NOT_APPLICABLE PostgreSQL |
| `expense_amount`, `expense_per_sqm`, `expense_revenue_share`, `utility_type`, `utility_tariff`, `utility_consumption` | расходы и коммунальная структура | внешний файл Power BI | `numeric` / `text` | UNKNOWN | расходный факт UNKNOWN | EXTERNAL / остаются в Power BI | решение пользователя 2026-07-30 | NOT_APPLICABLE PostgreSQL |
| `client_base_count` | факт КБ на выбранную дату | REUSE `mart.client_base_daily.client_count` | `bigint` | по контракту daily-КБ | дата×клуб×срез КБ | DESIGNED REUSE — ADR-0012/0024 | visual/DAX | daily coverage, no double sum scope |
| `active_base_rate` | активная КБ / КБ | current внешний набор Power BI | `numeric` | да | фильтр-контекст | EXTERNAL / NOT_APPLICABLE PostgreSQL — ADR-0024 | supplied DAX | Power BI control |
| `club_capacity`, `equipment_total`, `cardio_equipment`, `locker_count` | мощность, тренажёры, шкафчики по полу | внешний файл Power BI | `integer` | UNKNOWN | клуб / пол / effective period UNKNOWN | EXTERNAL / остаются в Power BI | решение пользователя 2026-07-30 | NOT_APPLICABLE PostgreSQL |
| `renew_rate` | `% Renew` выбранного месяца | внешний набор Power BI; `mart.contract_usage` не содержит готовый процент | `numeric` | UNKNOWN | месяц×клуб (candidate) | CONFIRMED consumer need / EXTERNAL boundary | решение пользователя 2026-07-30 | Power BI source |
| `visit_date`, `entry_hour`, `exit_hour`, `gender`, `age_years`, `visit_document_count` | компоненты максимальной ЧК | REUSE `mart.club_attendance_hourly` | `date` / `smallint` / `text` / `bigint` | по контракту hourly-факта | дата×клуб×час входа×час выхода×пол×возраст | DESIGNED REUSE — ADR-0022/0024 | M/DAX | TS-V04–TS-V05 |
| `max_concurrent_visit_count` | максимум сумм документов в часовом слоте | DAX over hourly fact; current inequalities preserved | `bigint` | да | date×club filter context | CONFIRMED current DAX | supplied DAX | exact-hour/open-entry control |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `AccumRg7370`, `AccumRg7575`, `AccumRg7646`, `AccumRg7739` | текущие ветви выручки | CONFIRMED source / states and keys pending | supplied M; revenue mappings |
| `Document325`, `Reference59`, `Reference70`, `Reference132`, `Reference141X1`, `Reference163` | текущая выручка/посещения и классификация | CONFIRMED current source / cardinality pending | supplied M; source catalog |
| `mart.revenue_group_summary_daily` | будущий переиспользуемый дневной факт выручки | DESIGNED / validation pending | data products catalog; ADR-0010 |
| `mart.client_base_daily` | ежедневная КБ для произвольной даты | CONFIRMED dependency / validation pending | data products catalog; client base/work attendance mappings |
| логический факт почасовой посещаемости | интервалы для максимальной ЧК | BUSINESS MAPPING COMPLETE / validation pending | work attendance mapping |
| внешние файлы КБ/Renew/расходов/характеристик | недостающие показатели | EXTERNAL / остаются в Power BI | решение пользователя 2026-07-30 |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `source_objects` | найдены все источники трёх выручечных M и посещений; внешние наборы остаются в Power BI | CONFIRMED |
| Проверенные продукты из `data_products` | найдены дневная выручка, ежедневная КБ и почасовой кандидат посещаемости | CONFIRMED |
| Проверенные правила | BR-001, BR-002, BR-003, BR-004, BR-007, BR-010, BR-013 | CONFIRMED; BR-003 validation pending for report |
| Сравнение гранулярности | выручка, КБ и интервалы посещения различны; объединение фактов запрещено | CONFIRMED |
| Сравнение ключей | устойчивые club/date keys требуются во всех наборах; их уникальность и physical types не подтверждены | VALIDATION_PENDING |
| Сравнение бизнес-семантики | доходные компоненты соответствуют текущей TS формуле; DPFU включает ИП; часовой показатель совпадает с `work_attendance` | CONFIRMED current logic |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | REUSE дохода; REUSE/EXTEND consumer КБ и часов; NOT_APPLICABLE для внешних наборов; NEW отсутствует | CONFIRMED |
| Причина решения | одинаковые grain/правила используются без копий; разные grain остаются отдельными фактами | CONFIRMED — BR-002 |
| Затронутые потребители | Свод выручка ГК, Работа с посещаемостью, Клиентская база, %Renew | CONFIRMED catalogs/mappings |

## Риски и дальнейшая валидация

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| VALIDATION_PENDING | выручечные ветви | дубли/неверный знак/состояния скрыты месячной агрегацией | TS-V01–TS-V03, затем сверка клуб×месяц |
| VALIDATION_PENDING | ЧК | непонятная единица строки и границы входа/выхода | TS-V04–TS-V05 |
| NOT_APPLICABLE | расходы и параметры клуба | внешние файлы остаются в Power BI | не включать в PostgreSQL по решению пользователя 2026-07-30 |
| NOT_APPLICABLE | КБ факт и активная база | внешний входной набор остаётся в Power BI | не включать в PostgreSQL по решению пользователя 2026-07-30 |
| NOT_APPLICABLE | Renew | внешний входной набор остаётся в Power BI | не выводить из `contract_usage` автоматически |
| REJECTED | единая таблица титульного листа | смешает несовместимые grain и размножит суммы | отдельные facts + общие dimensions |
