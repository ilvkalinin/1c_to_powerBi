# Source-to-target mapping: «Управление продлением»

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION DEFERRED`.
SQL и физические объекты пока не создаются.

## Гранулярность

> один заканчивающийся исходный контракт.

Технический ключ:

> `expiring_contract_id = Reference59.ID`.

Месяц окончания определяет когорту. Клиент не является ключом: один клиент
может иметь несколько контрактов.

## Основные поля контракта

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип PostgreSQL | NULL | Статус | Проверка |
|---|---|---|---|---|---|---|
| `expiring_contract_id` | стабильный ID исходного контракта | `Reference59.ID` | UNKNOWN | нет | CONFIRMED metadata | уникальность |
| `expiring_contract_code` | код для текущей Power BI-модели | `Reference59.Code` | `text` | нет | CONFIRMED current | уникальность |
| `client_id` | клиент контракта | `Reference59.Fld681` | UNKNOWN | нет | CONFIRMED metadata | orphan |
| `membership_start_date` | дата начала | `Reference59.Fld671::date` | `date` | нет | CONFIRMED | sentinel |
| `membership_end_date` | дата окончания и дата когорты | `Reference59.Fld672::date` | `date` | нет | CONFIRMED | end >= start |
| `contract_end_month` | месяц окончания | первый день `membership_end_date` | `date` | нет | CONFIRMED requirement | month boundary |
| `membership_term_days` | длительность | `Reference59.Fld693` | UNKNOWN numeric | нет | CONFIRMED field | единица |
| `access_club_id` | клуб доступа | `Reference59.Fld687` | UNKNOWN | нет | CONFIRMED metadata | orphan |
| `purchase_price` | цена покупки исходного контракта | текущий `SUM(AccumRg7739.Fld7749)` по контракту | `numeric` | да | CONFIRMED current / semantics pending | Active, sign, states |
| `visit_count` | посещения по исходному контракту | переиспользовать mapping и source-side агрегацию `AccumRg7575 → contract`, но считать по текущему состоянию | `bigint` | нет | CONFIRMED logical reuse / technical pending | rows vs documents |
| `usage_rate` | использование по сроку | `visit_count / Reference59.Fld693` | `numeric` | да | CONFIRMED formula | no sum |
| `average_monthly_visits` | среднемесячные посещения | `visit_count / inclusive active calendar months` | `numeric` | да | CONFIRMED formula | no sum |

## Продление

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип | NULL | Статус | Проверка |
|---|---|---|---|---|---|---|
| `renewed_by_month_close_flag` | продлён не позднее 1-го числа после месяца окончания | `renewal_activation_date <= contract_end_month + interval '1 month'` | `boolean` | нет | CONFIRMED requirement | boundary date |
| `renewed_current_flag` | продлён не позднее текущей даты | `renewal_activation_date <= current_date` | `boolean` | нет | CONFIRMED requirement | future activation |
| `next_contract_id` | ID выбранного следующего контракта | `Reference59` того же клиента; текущий lateral rule | UNKNOWN | да | ASSUMPTION current implementation | доказать связь |
| `next_contract_code` | код нового контракта | `next.Reference59.Code` | `text` | да | CONFIRMED current | unique |
| `renewal_activation_date` | отображаемая дата продления | `next.Reference59.Fld670::date` | `date` | да | CONFIRMED report definition | sentinel/backfill |
| `next_contract_start_date` | дата начала нового контракта | `next.Reference59.Fld671::date` | `date` | да | CONFIRMED source | overlap |
| `next_contract_term_days` | длительность нового контракта | `next.Reference59.Fld693` | UNKNOWN numeric | да | CONFIRMED | unit |
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
| `current_rating` | latest active `InfoRg6861` | current query / Active and ties pending |
| `current_tenure` | latest `InfoRg5654` | current query / ties pending |
| `last_interaction_at` | latest eligible `Reference67.Fld820` | current query / tie-break pending |
| `last_interaction_type` | `Reference67.Fld831` mapping | current query |
| `current_funnel_stage` | `Reference106.Fld1205 → Reference264` | current query |
| `current_fail_reason` | `Reference106.Fld1201 → Reference201` | current query |

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

1. `VALIDATION_PENDING — implementation blocker`: связь старого и нового контракта и tie-break.
2. `VALIDATION_PENDING — implementation blocker`: состояния исходного/нового контракта и возврата.
3. `VALIDATION_PENDING — implementation blocker`: уникальность кода контракта.
4. `VALIDATION_PENDING — implementation blocker`: кардинальности последних rating/tenure/interaction.
5. `VALIDATION_PENDING — implementation blocker`: цена покупки и знаки движений.
6. `UNKNOWN`: фактические типы, размеры и планы. Данные должны быть доступны
   не позднее 08:30 по Москве (`CONFIRMED`, BR-014).
