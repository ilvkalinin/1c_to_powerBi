# Source-to-target mapping: маркетинговая воронка

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE REUSE CONFIRMED / TECHNICAL VALIDATION REQUIRED`.

Гранулярность одной строки: одно CRM-задание `Reference106.ID` в воронке
«Продажа клубной карты». Логический ключ: `task_id`; физический тип и
уникальность `VALIDATION_PENDING`.

Целевой набор повторно использует `mart.fitness_leads_funnel_task`; ниже
зафиксирована только проекция, нужная маркетинговому отчёту. Планы остаются
внешними таблицами Power BI и не являются колонками PostgreSQL-набора.

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
| `contract_id`, `contract_name` | атрибутированный контракт | `InfoRg6798.Fld6800_RRRef → Reference59.ID/Description` | `_Fld6802=true`, исключить клип-карту и бесплатный тип оплаты | UNKNOWN, text | да | task | CONFIRMED current / cardinality pending | SQL/M | MF-V03, MF-V06 |
| `activation_date` | дата активации контракта | `Reference59.Fld670` | `::date`; current history с 2024-01-01 | date | да | task | CONFIRMED current | SQL/M | MF-V01, MF-V06 |
| `contract_age_group` | возрастная группа покупки | `Reference59.Fld696`, `Reference163.Fld1741` | current CASE: детские секции / взрослые / дети / юниоры; fallback взрослые | text | да | task | CONFIRMED current | SQL/M | MF-V05, MF-V07 |
| `contract_payment_type` | тип оплаты покупки | `Reference59.Fld699` | GUID: рекарринг, иначе предоплата | text | да | task | CONFIRMED current | SQL/M | MF-V05, MF-V07 |
| `contract_duration_group` | длительность покупки | `Reference59.Fld693` | дни: `001–007`, `008–030`, `031–180`, `181–364`, `365+` | text | да | task | CONFIRMED current | SQL/M | MF-V07 |
| `task_count` | вклад в число заданий | `task_id` | `1`; мера — distinct task key и удаляет contract-фильтры | smallint | нет | task | CONFIRMED current | DAX | MF-V02, MF-V09 |
| `contract_count` | вклад в число абонементов | `contract_id` | `1` после подтверждённой дедупликации; до MF-V03 не реализовывать как строковую сумму | smallint | UNKNOWN | task | VALIDATION_PENDING | current DAX | MF-V03, MF-V09 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `Reference106`, `Reference89`, `Reference132`, `Reference141X1`, `Reference145`, `Reference201`, `Reference264` | CRM-задание и измерения | CONFIRMED current source | SQL/M «Задания 2026» |
| `InfoRg6798`, `Reference59`, `Reference163` | связь задачи с контрактом и атрибуты купленного контракта | CONFIRMED current source; physical key/cardinality pending | CTE `contracts` |
| `Новые планы`, `Подневный план по трафику` | дневные планы | EXTERNAL / Excel в Power BI | решение пользователя 2026-07-30; текущая DAX |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `docs/catalogs/source_objects.md` | CRM-задания, справочники и контракты каталогизированы; `InfoRg6798` добавлен как подтверждённый current source. | CONFIRMED catalog / validation pending |
| Проверенные продукты из `docs/catalogs/data_products.md` | `mart.fitness_leads_funnel_task` имеет тот же task grain и уже хранит задачу, кампанию, тип взаимодействия и task-to-contract enrichment. | CONFIRMED catalog / ADR-0011 |
| Проверенные правила из `docs/catalogs/business_rules.md` | BR-001 (компактное извлечение), BR-002 (reuse по grain), BR-007 (защита ключа клиента) применимы. | CONFIRMED |
| Сравнение гранулярности | оба отчёта используют одно CRM-задание; планы являются отдельным внешним `дата × срез` набором. | CONFIRMED match |
| Сравнение ключей | базовый ключ обоих наборов — `task_id`; task code используется current SQL только для contract bridge. | CONFIRMED / validation pending |
| Сравнение бизнес-семантики | фитнес-отчёт считает тренировочные outcomes, маркетинговый — подходящие активированные контракты, но CRM task core совпадает. | CONFIRMED; outcomes не переносятся |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | `REUSE`: `mart.fitness_leads_funnel_task`; отдельная витрина/копия CRM не требуется. | DESIGNED reuse / contract `marketing_funnel` / technical validation required |
| Причина решения | новый факт дублировал бы одну и ту же задачу и её CRM-атрибуты; маркетинговые меры и планы могут оставаться в Power BI. | CONFIRMED |
| Затронутые существующие потребители | «Воронка лиды фитнес» и «Воронка». | CONFIRMED |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| `VALIDATION_PENDING` | `task → contract` | возможен bridge `1:N`; число контрактов и конверсия могут быть размножены | MF-V03, MF-V04 |
| `VALIDATION_PENDING` | task code в bridge | current SQL соединяет отображаемые коды | MF-V02; перейти на ID только после доказательства physical field |
| `VALIDATION_PENDING` | когорты накопленного трафика | current DAX использует годовые таблицы и несколько промежуточных мер | MF-V08, MF-V09 |
| `VALIDATION_PENDING` | сеть/кластер | общий mapping клуба подтверждён; физические поля и покрытие клубов ещё не проверены | MF-V01 |
| `NOT_APPLICABLE` | внешние планы и watermark | Excel-планы остаются в Power BI | не включать в PostgreSQL SQL по решению пользователя 2026-07-30 |
