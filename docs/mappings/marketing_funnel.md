# Source-to-target mapping: маркетинговая воронка

Статус: `IMPLEMENTED / SOURCE-TO-TARGET RECONCILED / NEW MINIMAL TASK + CONTRACT FACTS / BR-003 RETENTION CONFIRMED`.

CRM core имеет grain одно задание `Reference106.ID`. Для метрики
«Абонементы факт» используется отдельная логическая проекция: одна
квалифицированная связь `task_id × contract_id`. Её состав задаёт BR-020;
task code подтверждён в отчётном scope по SV-101. Технический ключ target
bridge проверяется при приёмке созданной проекции; это не открывает новый
source-side control global gate.

Целевой набор состоит из `mart.marketing_funnel_task` и
`mart.marketing_funnel_task_contract`. Планы остаются внешними таблицами
Power BI и не являются колонками PostgreSQL-набора.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица / колонка | Преобразование | PostgreSQL тип | NULL | Grain | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|
| `task_id` | стабильный ключ задания | `Reference106.ID` | без преобразования | UNKNOWN | нет | task | CONFIRMED source | SQL/M | MF-V02 |
| `task_code` | отображаемый код задания | `Reference106.Code` | не использовать как ключ до MF-V02 | text | нет | task | CONFIRMED source | SQL/M | MF-V02 |
| `task_created_at` | дата и время создания | `Reference106.Fld1193` | без преобразования | timestamp UNKNOWN | нет | task | CONFIRMED source | SQL/M | MF-V01, MF-V06 |
| `task_date` | дата календарного отбора и заданий | `Reference106.Fld1193` | `task_created_at::date` | date | нет | task | CONFIRMED current | M/DAX | MF-V01 |
| `closed_at`, `forced_closed_at` | даты закрытия задания | `Reference106.Fld1192`, `Fld8772` | без преобразования | timestamp UNKNOWN | да | task | CONFIRMED source | SQL/M | MF-V01, MF-V08 |
| `funnel_id`, `funnel_name` | CRM-воронка | `Reference106.Fld1191 → Reference89.ID/Description` | только «Продажа клубной карты» | UNKNOWN, text | нет | task | CONFIRMED current | SQL/M | MF-V04, MF-V05 |
| `club_id`, `club_name` | клуб задания | `Reference106.Fld1195 → Reference132.ID/Description` | исключить «Детский развивающий центр» | UNKNOWN, text | да | task | CONFIRMED current | SQL/M | MF-V04 |
| `network_name`, `cluster_name` | сеть и кластер задания | `Reference132` через общий mapping клуба | не дублировать mapping в факте; получать по `club_id` | text, text | да | task | CONFIRMED common rule / physical fields pending | решение пользователя 2026-07-30; source catalog | MF-V01 |
| `client_key`, `client_code` | безопасный ключ и отображаемый код клиента | `Reference106.Fld1196 → Reference141X1.ID/Code` | ключ защищён; способ защиты определяется общим контрактом | UNKNOWN, text | да | task | CONFIRMED current / protection pending | SQL/M, BR-007 | MF-V01, MF-V02 |
| `tenure_type` | New / Ex / Renew | `Reference106.Fld1190` | текущий mapping GUID | text | да | task | CONFIRMED current | SQL/M | MF-V05 |
| `campaign_id`, `campaign_name`, `parent_campaign_name` | кампания и родитель | `Reference106.Fld1197 → Reference145` | `NULL` родителя → `НетРодителя` только для текущей классификации | UNKNOWN, text, text | да | task | CONFIRMED current | SQL/M | MF-V04 |
| `unsuccessful_reason` | причина неуспеха | `Reference106.Fld1201 → Reference201.Description` | исключить два exact значения дубля | text | да | task | CONFIRMED current | SQL/M | MF-V04, MF-V05 |
| `funnel_stage_name` | этап CRM-воронки | `Reference106.Fld1205 → Reference264.Description` | без преобразования | text | да | task | CONFIRMED current | SQL/M | MF-V04 |
| `first_interaction_type_raw` | исходный тип первого взаимодействия | `Reference106.Fld8712` | mapping фиксированных GUID | text | да | task | CONFIRMED current | SQL/M | MF-V05 |
| `first_interaction_type` | тип для визуала | `first_interaction_type_raw`, `parent_campaign_name` | M-классификация: выделенные типы; `Промо* → Мероприятия`; остальное → Прочие | text | нет | task | CONFIRMED current | M | MF-V05 |
| `traffic_direction` | маркетинг/продажи и входящий/исходящий накопленный трафик | `first_interaction_type` | исходящий: звонок, чат, регистрация рекомендации; остальные — входящий | text | нет | task | CONFIRMED current DAX | DAX | MF-V08 |
| `contract_id`, `contract_name` | атрибутированный контракт | `InfoRg6798.Fld6800_RRRef → Reference59.ID/Description` | `_Fld6802=true`, исключить клип-карту и бесплатный тип оплаты; сохранить каждую candidate `task × contract` связь с activation history; удалить только полные технические повторы `DISTINCT` | UNKNOWN, text | да | task × contract | CONFIRMED — 19 exact source duplicates verified 2026-08-24 | current SQL/M, MF-DIAG-001—002 | MF-V03, MF-V06, MF-DIAG-001—002 |
| `activation_date` | дата активации контракта | `Reference59.Fld670` | `IS NOT NULL`; сохранять полную history до BR-003 task horizon, потому что current DAX вычитает клиентов с активацией до контрольного месяца; BR-020 не удаляет link, а вычисляется отдельным флагом | date | нет | task × contract | CONFIRMED current DAX + BR-020 | MF-V08, BR-020, MF-FIX-002 | MF-V01, MF-V06, MF-V08, MF-FIX-002 |
| `contract_age_group` | возрастная группа покупки | `Reference59.Fld696`, `Reference163.Fld1741` | current CASE: детские секции / взрослые / дети / юниоры; fallback взрослые | text | да | task | CONFIRMED current | SQL/M | MF-V05, MF-V07 |
| `contract_payment_type` | тип оплаты покупки | `Reference59.Fld699` | BR-024: `9bd3ea4748457ee94b2011de6d9687d7` → рекарринг, другой non-NULL → предоплата | text | да | task | VALIDATED common rule — MF-V07C | current M + BR-024 | MF-V05, MF-V07C |
| `contract_duration_group` | длительность покупки | `Reference59.Fld693` | дни: `001–007`, `008–030`, `031–180`, `181–364`, `365+`; неположительное значение не переклассифицируется без правила | text | да | task | VALIDATED WITH ANOMALY — MF-V07 | SQL/M | MF-V07 |
| `task_count` | вклад в число заданий | `task_id` | `1`; мера — distinct task key и удаляет contract-фильтры | smallint | нет | task | CONFIRMED current | DAX | MF-V02, MF-V09 |
| `is_conversion_qualified` | прошла ли candidate link BR-020 | `activation_date`, `task_created_at` | `activation_date >= task_created_at::date` | boolean | нет | task × contract | CONFIRMED — user decision | BR-020 | MF-V03G, MF-V03H |
| `contract_count` | вклад в число абонементов | candidate `task_id × contract_id` | `1` только при `is_conversion_qualified`, иначе `0`; не применять global `DISTINCT(contract_id)` | smallint | нет | task × contract | CONFIRMED — user decision | BR-020 | MF-V03G, MF-V03H, MF-V09 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `Reference106`, `Reference89`, `Reference132`, `Reference141X1`, `Reference145`, `Reference201`, `Reference264` | CRM-задание и измерения | CONFIRMED current source | SQL/M «Задания 2026» |
| `InfoRg6798`, `Reference59`, `Reference163` | связь задачи с контрактом и атрибуты купленного контракта | CONFIRMED current source; physical key/cardinality reconciled | MF-LOAD-003, MF-R01—MF-R05 |
| `Новые планы`, `Подневный план по трафику` | дневные планы | EXTERNAL / Excel в Power BI | решение пользователя 2026-07-30; текущая DAX |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `docs/catalogs/source_objects.md` | CRM-задания, справочники и контракты каталогизированы; `InfoRg6798` добавлен как подтверждённый current source. | CONFIRMED catalog / validation pending |
| CRM `mart.crm_interaction` | interaction grain и sales/guest scope не покрывают task scope маркетинговой воронки. | CONFIRMED mismatch / `NOT_APPLICABLE` |
| Выручечные продукты `mart.ancillary_revenue_movement`, `mart.ip_revenue_daily` | revenue/service-movement grain не содержит CRM task или BR-020 contract link. | CONFIRMED mismatch / `NOT_APPLICABLE` |
| `mart.fitness_leads_funnel_task` | product физически отсутствует; его future four-funnel/outcome scope шире маркетингового пакета. | CONFIRMED catalog / `NOT_APPLICABLE` for physical reuse |
| Проверенные правила из `docs/catalogs/business_rules.md` | BR-001 (компактное извлечение), BR-002 (reuse по grain), BR-007 (защита ключа клиента) применимы. | CONFIRMED |
| Сравнение гранулярности | оба отчёта используют одно CRM-задание; планы являются отдельным внешним `дата × срез` набором. | CONFIRMED match |
| Сравнение ключей | базовый ключ обоих наборов — `task_id`; task code используется current SQL только для contract bridge. | CONFIRMED / target key reconciled by MF-R02 |
| Сравнение бизнес-семантики | фитнес-отчёт считает тренировочные outcomes, маркетинговый — подходящие активированные контракты, но CRM task core совпадает. | CONFIRMED; outcomes не переносятся |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | `NEW`: `mart.marketing_funnel_task` и `mart.marketing_funnel_task_contract`; без raw-replica, постоянного staging или revenue join. | CONFIRMED planning decision / ADR-0032 |
| Причина решения | две нужные grain не совпадают с физически доступными продуктами; создание широкой будущей fitness-leads витрины расширило бы scope. | CONFIRMED |
| Затронутые существующие потребители | Только «Воронка»; пользователь 2026-08-24 подтвердил, что future fitness-leads product не расширяет этот пакет. | CONFIRMED user decision |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| `VALIDATED business rule / Stage 3 target control` | `task → contract` | SV-080: 100 строк bridge соответствуют 36 заданиям; у 21 задания более одного контракта. MF-DIAG-001—002: 19 групп source bridge содержат только точные повторные строки. | Bridge сохраняет current candidate links; BR-020 выдаёт `contract_count=1` только qualifying rows. `DISTINCT` разрешён только для полного технического повтора уже подтверждённой пары; не добавлять global dedup по contract. |
| `VALIDATED in report scope` | task code в bridge | SV-101: current DAX-code уникален без `NULL` в report funnel; physical join остаётся по ID. | Не использовать code как physical bridge key; Stage 3 проверяет target ID-based key. |
| `CONFIRMED user-approved PBIT / VALIDATION_PENDING physical` | когорты накопленного трафика | `UNION(Задания 2024, Задания 2025)`; два предыдущих календарных месяца; минус отмены до месяца и distinct clients по task с контрактом, активированным до месяца. Фильтры оплаты/длительности/возраста снимаются; обе traffic-категории получают один итог. | MF-V08, MF-V09 |
| `VALIDATED WITH ANOMALY` | длительность контракта | В report funnel одна qualified связь имеет неположительную `Fld693`; `NULL` нет. | MF-V07; current boundaries сохраняются, строка не исключается без решения. |
| `VALIDATED` | тип оплаты контракта | BR-024 задаёт единое для отчётов значение рекарринга; MF-V07C подтвердил его покрытие в report funnel. | 9 238 рекарринговых и 191 625 предоплатных `task × contract` связей; `NULL` = 0. |
| `VALIDATED WITH NULL RISK` | CRM dimension joins | SV-101: joins не размножают task; незаполненные club/campaign/reason/stage сохраняются как `NULL`, не фильтруются. | MF-V04 |
| `VALIDATION_PENDING` | сеть/кластер | общий mapping клуба подтверждён; физические поля и покрытие клубов ещё не проверены | MF-V01 |
| `CONFIRMED user decision` | retention | Пользователь 2026-08-24 выбрал BR-003, а не static PBIT exception: в августе 2026 хранится `[2025-01-01, 2027-01-01)`. | Source extract uses parameterised BR-003 bounds; current PBIT 2024–2025 remains evidence only. |
| `NOT_APPLICABLE` | внешние планы и watermark | Excel-планы остаются в Power BI | не включать в PostgreSQL SQL по решению пользователя 2026-07-30 |

## Evidence Stage 2: SV-080

Контроль выполнен в gymdb только на чтение после текущих фильтров
`InfoRg6798`: 100 строк bridge дали 36 CRM-заданий; 21 задание имеет более
одного контракта. В заданиях с несколькими контрактами — 85 связей
`task × contract`,
максимум 16 контрактов на одно задание. Поэтому one-to-one связь не подтверждена, а
BR-020 задаёт `contract_count = 1` на квалифицированной связи; проверенный task
core реализуется отдельно как `mart.marketing_funnel_task`, а bridge — как
`mart.marketing_funnel_task_contract`. MF-V03G исключил ошибочную пару `0000302905`: 2 технические связи,
0 после дат 2024-01-01 и создания задания. MF-V03H измерил временно
квалифицированный source bridge после current contract filters: 199 450 rows,
184 206 tasks, 12 537 multi-contract tasks, 199 093 contracts и 334
multi-task contracts. Это observation без dedup, не итоговая отчётная мера.

MF-V03 измерял только направление `task → contract`. Отдельный MF-V03F,
выполненный в `BEGIN READ ONLY` 2026-08-13 по запросу пользователя, подтвердил
обратную множественность: контракт `0000302905` связан с заданиями `008259075`
и `008854940`. Нельзя интерпретировать aggregate MF-V03 как доказательство
этого направления.
