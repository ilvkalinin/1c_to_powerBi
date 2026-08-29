# Source-to-target mapping: «Управление продлением»

Статус: `IMPLEMENTED / Stage 3 VALIDATED — RM-LOAD-001—006`.
Reviewed SQL, physical target, final source-to-target reconciliation and clean timed rerun are validated.

## Гранулярность

> один заканчивающийся исходный контракт.

Технический ключ:

> `expiring_contract_id = Reference59.ID`.

Месяц окончания определяет когорту. Клиент не является ключом: один клиент
может иметь несколько контрактов.

## Основные поля контракта

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип PostgreSQL | NULL | Статус | Проверка |
|---|---|---|---|---|---|---|
| `expiring_contract_id` | стабильный ID исходного контракта | `Reference59.ID`, hex rendered | `text` | нет | CONFIRMED RM-S2-01/08 | uniqueness |
| `expiring_contract_code` | код для текущей Power BI-модели | `Reference59.Code` | `text` | нет | CONFIRMED current | уникальность |
| `client_id` | клиент контракта | `Reference59.Fld681`, hex rendered | `text` | нет | CONFIRMED RM-S2-08 | orphan |
| `membership_start_date` | дата начала | `Reference59.Fld671::date` | `date` | нет | CONFIRMED | sentinel |
| `membership_end_date` | дата окончания и дата когорты | `Reference59.Fld672::date` | `date` | нет | CONFIRMED | end >= start |
| `contract_end_month` | месяц окончания | первый день `membership_end_date` | `date` | нет | CONFIRMED requirement | month boundary |
| `membership_term_days` | длительность | `Reference59.Fld693` | `numeric` | нет | CONFIRMED RM-S2-08 | unit semantics preserved |
| `access_club_id` | клуб доступа | `Reference59.Fld687`, hex rendered | `text` | нет | CONFIRMED RM-S2-08 | orphan |
| `purchase_price` | цена покупки исходного контракта | current `SUM(AccumRg7739.Fld7749)` by contract, `Period > 2015-01-01`, `RecordKind=0`; no Active filter | `numeric` | да | CONFIRMED current / RM-S2-06 | active/sign observations preserved BR-018 |
| `visit_count` | посещения по исходному контракту | current 2026 `AccumRg7575 → Reference59` path grouped by contract code, rendered to confirmed unique contract ID | `bigint` | нет | CONFIRMED current / RM-S2-07 | `COUNT(*)`, no state filter |
| `usage_rate` | использование по сроку | `visit_count / Reference59.Fld693` | `numeric` | да | CONFIRMED formula | no sum |
| `average_monthly_visits` | среднемесячные посещения | `visit_count / inclusive active calendar months` | `numeric` | да | CONFIRMED formula | no sum |

## Продление

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип | NULL | Статус | Проверка |
|---|---|---|---|---|---|---|
| `renewed_by_month_close_flag` | продлён не позднее 1-го числа после месяца окончания | `renewal_activation_date <= contract_end_month + interval '1 month'` | `boolean` | нет | CONFIRMED requirement | boundary date |
| `renewed_current_flag` | продлён не позднее текущей даты | `renewal_activation_date <= current_date` | `boolean` | нет | CONFIRMED requirement | future activation |
| `next_contract_id` | ID выбранного следующего контракта | same client → earliest start → paid before free → min technical ID | `text` | да | CONFIRMED BR-050 | RM-S2-02 |
| `next_contract_code` | код нового контракта | `next.Reference59.Code` | `text` | да | CONFIRMED current | unique |
| `renewal_activation_date` | отображаемая дата продления | `next.Reference59.Fld670::date` | `date` | да | CONFIRMED report definition | sentinel/backfill |
| `next_contract_start_date` | дата начала нового контракта | `next.Reference59.Fld671::date` | `date` | да | CONFIRMED source | overlap |
| `next_contract_term_days` | длительность нового контракта | `next.Reference59.Fld693` | `numeric` | да | CONFIRMED RM-S2-08 | unit semantics preserved |
| `renewal_type` | платное / бесплатное короткое / бесплатное длинное / нет | `next.Fld699 + next.Fld693` | `text`/code | нет | CONFIRMED current CASE | numerator decision |
| `renewal_lead_lag_days` | дней до/после окончания | `renewal_activation_date - membership_end_date` | `integer` | да | PROPOSED | negative/positive controls |
| `return_days` | дней возврата после разрыва | `greatest(renewal_lead_lag_days,0)` для продлённых | `integer` | да | PROPOSED | not renewed = NULL |
| `return_bucket` | категория скорости возврата | до окончания; 0–30; 31–60; 61–90; 91–180; 181+ | code/text | да | PROPOSED | boundaries |

`%Renew на 1-е число` и `%Renew итоговый` физически не хранятся. DAX делит
сумму соответствующего флага на один и тот же distinct-набор исходных
контрактов когорты. Снимки и версии одной строки не создаются.

## Текущие клиентские атрибуты

| Целевая колонка | Источник | Статус / правило |
|---|---|---|
| `client_name`, `client_phone` | `Reference141.Description/Fld1531` | CONFIRMED consumer; PII |
| `birth_date` | `Reference141.Fld1507` | CONFIRMED source |
| `current_rating` | latest period `InfoRg6861`; current CASE mapping | `text` | CONFIRMED RM-S2-04/current M; no Active predicate |
| `current_tenure` | latest period `InfoRg5654`; current CASE mapping | `text` | CONFIRMED RM-S2-04/current M; no Active predicate |
| `last_interaction_at` | latest eligible `Reference67.Fld820`; min technical ID at same timestamp | `timestamp` | да | CONFIRMED BR-050 | RM-S2-05 |
| `last_interaction_type` | `Reference67.Fld831` mapping on selected row | `text` | да | CONFIRMED BR-050 | RM-S2-05 |
| `current_funnel_stage` | `Reference106.Fld1205 → Reference264` on selected row | `text` | да | CONFIRMED BR-050 | RM-S2-05 |
| `current_fail_reason` | `Reference106.Fld1201 → Reference201` on selected row | `text` | да | CONFIRMED BR-050 | RM-S2-05 |

Эти поля являются текущим состоянием клиента и обновляются ежедневно; они не
описывают состояние на дату окончания.

## Отбор исходной когорты

Текущие правила сохраняются как mapping, но не считаются технически
подтверждёнными:

- исходный контракт не клип-карта, не бесплатный и не подписка;
- срок не менее 30 дней;
- описание не содержит ИП/сотрудника;
- клиент заполнен;
- `ПереданС` равен sentinel;
- отсутствует строка `Document332.АбонементЗачета`;
- отсутствует `Document287` по абонементу.

`Document287` должен проверяться по подтверждённым `Posted`, `Marked` и статусу.
`Document332.АбонементЗачета` не называется возвратом в metadata.

## Повторное использование и границы

- из `%Renew` переиспользуются доказательства источника, mapping и формулы
  посещений, срока и коэффициентов;
- физический `mart.contract_usage` не переиспользуется: его frozen-семантика не
  соответствует текущему состоянию этого отчёта;
- Renew-флаги, PII, CRM, рейтинг и цена остаются в объекте этого отчёта;
- сырые `AccumRg7575` повторно не копируются;
- общий клиентский справочник возможен только после подтверждения
  потребителей и доступа к PII.

## Решения и блокеры

1. `CONFIRMED BR-050`: 93 next-start and 96 interaction ties have an explicit deterministic selection; no new source-state filter is introduced.
2. `CONFIRMED RM-S2-01/03/04/06/07/08`: cohort key/code, rating/tenure cardinality, price and visit technical keys, and physical types are evidenced. Current no-state predicates and price `RecordKind=0` remain preserved under BR-018.

## Stage 2 evidence — SV-081 (2026-08-11)

Все 18 физических relations существуют. Ограниченная выборка 100 контрактов
подтвердила текущий contract grain после `Document332`/`Document287`: 100
строк, 100 distinct ID, `duplicate_contract_groups = 0`. В 51 строке найден
next-contract; `earliest_start_tie_groups = 0` в выборке. Это не превращает
эвристику same-client/date в доказанную прямую связь и не закрывает
full-population проверку.

Для 100 клиентов `InfoRg6861` и `InfoRg5654` не дали ties на latest period.
Цена: 1 448 source rows = 1 448 technical keys, orphan contract = 0,
неактивных = 4; legacy `RecordKind = 0` не меняется. Посещения на том же
bounded scope: legacy `COUNT(*)`, technical keys и distinct documents равны
133; ресурс `Fld7585 = 133.00`. Технические состояния документов и единица
посещаемости остаются `VALIDATION_PENDING` для полного источника.
