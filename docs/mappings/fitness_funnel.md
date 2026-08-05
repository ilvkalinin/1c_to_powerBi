# Source-to-target mapping: фитнес воронка

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0026 / TECHNICAL VALIDATION REQUIRED`.
Production SQL не создаётся. Все физические имена и поля ниже подтверждены
только текущими SQL/M; их типы, ключи, состояния и кардинальности имеют статус
`VALIDATION_PENDING`.

## Гранулярность

Целевая гранулярность:

> один уникальный клиент × дата начала нового контракта.

Логический ключ: `(client_key, membership_start_date)`. Несколько контрактов
клиента в одну дату сворачиваются в одну cohort-строку по решению пользователя
2026-07-30; `contract_id` не является ключом и не участвует в мерах.

Исходы вынесены во второй набор с grain `клиент × дата исхода × вид исхода ×
источник`. Это позволяет одному набору мер применять периодные окна 1/2/12,
а другому — as-of правило рабочего списка, не создавая несовместимый флаг в
cohort-строке.

Поля конкретного контракта остаются дочерней detail-проекцией с grain
`клиент × дата старта × контракт`; она не связана с агрегатами воронки и не
может изменить число клиентов cohort.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Источник таблица / колонка | Преобразование | PostgreSQL тип | NULL | Grain | Статус | Доказательство | Тест |
|---|---|---|---|---|---|---|---|---|---|
| `client_key` | стабильный обезличенный ключ клиента | `Reference59.Fld681` | защищённое представление | UNKNOWN | нет | client-start | CONFIRMED — user decision 2026-07-30, BR-007 | V-01, V-04 |
| `membership_start_date` | дата старта client cohort | `Reference59.Fld671` | `::date`; distinct вместе с `client_key` | date | нет | client-start | CONFIRMED — user decision 2026-07-30 | V-01, V-02 |
| `contract_code` | код контракта для detail | `Reference59.Code` | без агрегации; не использовать в мерах | text | нет | client-start-contract detail | CONFIRMED — business description, user decision 2026-07-30 | V-02 |
| `membership_end_date` | окончание контракта | `Reference59.Fld672` | `::date` | date | нет | client-start-contract detail | CONFIRMED source | SQL/M/DAX | V-01, V-02 |
| `activation_date` | дата активации | `Reference59.Fld670` | `::date` | date | да | client-start-contract detail | CONFIRMED source | SQL/M | V-01 |
| `membership_term` | срок действия | `Reference59.Fld693` | current filter `> 6` | numeric UNKNOWN | нет | client-start-contract detail | CONFIRMED current | SQL/M | V-01, V-02 |
| `tenure_type` | New / Ex / Renew | `Reference59.Fld694` | current GUID decode | text | нет | client-start-contract detail | CONFIRMED current | SQL/M | V-01 |
| `contract_type_id` | тип контракта | `Reference59.Fld696` | исключить current GUID clip-карты | UNKNOWN | нет | client-start-contract detail | CONFIRMED current | SQL/M | V-01, V-08 |
| `client_code` | код клиента для текущего detail | `Reference141X1.Code` | join client; не использовать как ключ | text | нет | client-start | CONFIRMED current | SQL/M/DAX | V-01, V-04 |
| `client_name`, `client_phone` | PII detail table | `Reference141X1.Description`, `Reference141X1.Fld1531` | detail для работы с клиентом | text | да | client-start | CONFIRMED — business description, user decision 2026-07-30 | V-11 |
| `access_club_id`, `access_club_name` | клуб доступа контракта | `Reference59.Fld687 → Reference132.ID/Description` | join | UNKNOWN, text | да | client-start-contract detail | CONFIRMED current | SQL/M | V-01, V-11 |
| `outcome_client_key` | защищённый ключ клиента исхода | `InfoRg7006.Fld7008`; `AccumRg7575.Fld7576`; `AccumRg7646.Fld7648` | привести к представлению `client_key` | UNKNOWN | нет | client-outcome-event | CONFIRMED current source, BR-007 | V-01, V-04 |
| `outcome_date` | дата квалифицированного исхода | СПТ: `Document329.Fld4306`; ДПФУ: `AccumRg7575.Period` / `AccumRg7646.Period`; ИП: `Document329.Fld4306` / `Document279.Fld3218` | `::date` | date | нет | client-outcome-event | CONFIRMED — SQL/M/DAX, user decision 2026-07-30 | V-01, V-06, V-08 |
| `outcome_type` | СПТ, ДПФУ или Гайд | те же event sources | literal by qualified source branch | text | нет | client-outcome-event | CONFIRMED current | SQL/M/DAX | V-06, V-07 |
| `outcome_event_count` | вклад события в среднее ДПФУ | ДПФУ/ИП source branch | `1` per current result row; DAX aggregates only the qualified types | bigint | нет | client-outcome-event | CONFIRMED current / source grain pending | DAX | V-06, V-08 |
| `outcome_club_id` | клуб события для фильтра | `InfoRg7006.Fld7009`; `AccumRg7575.Fld7577`; `AccumRg7646.Fld7653` | без текстового сравнения в target | UNKNOWN | да | client-outcome-event | CONFIRMED current source / ID validation pending | SQL/M | V-01, V-08 |
| `outcome_employee_id` | сотрудник события для detail | `Document329.Fld4322`, `Document279.Fld3223`, `AccumRg7575.Fld7582`, `AccumRg7646.Fld7652` | без преобразования; multiple events остаются отдельными строками | UNKNOWN | да | client-outcome-event | CONFIRMED current | SQL/M/DAX | V-04, V-06 |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `Reference59`, `Reference141X1`, `Reference132` | контракт, клиент, клуб доступа | CONFIRMED current source | `Спр Абонементы` |
| `InfoRg7006`, `Document329`, `Document279`, `Document325`, `Enum448`, `Reference163` | СПТ, ИП и Гайд | CONFIRMED current source; keys/states pending | SQL/M |
| `AccumRg7575`, `AccumRg7646`, `Reference70`, `Reference225` | движения ДПФУ, вид деятельности и сотрудник | CONFIRMED current source; keys/states pending | SQL/M |
| `Document283` | текущая ветка отмен «Гайд» | CONFIRMED current source; join semantics pending | SQL/M |
| `InfoRg6291` | текущая настройка активных сотрудников | CONFIRMED current source; historical interval pending | SQL/M |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из каталога | Контракты, посещения, предзапись, ИП, ДПФУ, сотрудник уже каталогизированы. | CONFIRMED catalog / validation pending |
| Проверенные продукты из каталога | `mart.contract_usage`, newcomer facts, факт тренировок ИП и общий ancillary факт. | CONFIRMED catalog |
| Проверенные правила из каталога | BR-001 компактное извлечение, BR-002 reuse только при совпадении grain/семантики, BR-007 protected client key, BR-009 отдельный факт ИП, BR-012 source-rule reuse. | CONFIRMED |
| Сравнение гранулярности | `mart.contract_usage` — контракт; newcomer — контракт × клиент × checkpoint; ИП/ДПФУ — события. Отчёту нужна cohort `клиент × дата старта`. | CONFIRMED mismatch |
| Сравнение ключей | `contract_id` не является ключом отчёта; outcome-источники сопоставляются с `client_key`. | CONFIRMED — user decision 2026-07-30 |
| Сравнение бизнес-семантики | `%Renew` считает использование контракта; этот отчёт показывает работу с клиентом после даты старта. | CONFIRMED mismatch |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | `NEW`: cohort «фитнес-воронка: старт клиента» и его client-outcome event set. | ACCEPTED — user decision 2026-07-30 |
| Причина решения | `EXTEND` контрактных продуктов нарушит их grain и повторно введёт contract attribution outcomes; статический outcome flag потеряет разные DAX-окна. | CONFIRMED analysis |
| Затронутые существующие потребители | `%Renew`, «Управление продлением», «Вовлечение новичков», KPI Фитнеса, «Подготовка к продлению». | CONFIRMED catalog; degree of reuse pending |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| CONFIRMED | Несколько контрактов клиента в дату | Сворачиваются в одну client-start cohort; contract link не нужен. | user decision 2026-07-30 |
| CONFIRMED | СПТ/ДПФУ → контракт | Эта связь исключена из целевой семантики. | user decision 2026-07-30 |
| VALIDATION_PENDING | статусы и отмены | Нет доказательства `Active`/`Posted`/`Marked` и ключа отмены. | V-07. |
| CONFIRMED | Разные окна СПТ/ДПФУ | Периодные и as-of меры используют одну дату исхода, но разные DAX-фильтры. | SQL/M/DAX, user decision 2026-07-30 |
| CONFIRMED | PII detail | ФИО и телефон нужны для работы с клиентом в detail-таблице; доступны всем пользователям с доступом к отчёту. | business description, user decisions 2026-07-30 and 2026-07-31; BR-017 |
