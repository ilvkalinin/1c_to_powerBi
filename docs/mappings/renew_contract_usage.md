# Source-to-target mapping: использование контрактов для %Renew

Статус: `IMPLEMENTED / initial load and atomic rerun VALIDATED — CU-LOAD-001—008`.
Physical target создан и принят 2026-08-28; Power BI не менялся по BR-036.

## Гранулярность

> один контракт.

Технический ключ:

> `contract_id = encode(Reference59.ID, 'hex')::text` в target.

`contract_code` сохраняется только как ключ связи с существующей выгрузкой 1С,
пока та не начнёт передавать бинарный ID контракта.

## Mapping

| Целевая колонка | Бизнес-описание | Источник / преобразование | PostgreSQL тип | NULL | Статус / доказательство | Проверка |
|---|---|---|---|---|---|---|
| `contract_id` | стабильный ID контракта | `encode(Reference59.ID, 'hex')` | `text` | нет | CONFIRMED Stage 3 representation | CU-S01, PK |
| `contract_code` | код для связи с существующей выгрузкой 1С | `Reference59.Code::text` | `text` | нет | full dynamic BR-003 CU-S02 passed; `UNIQUE` accepted | CU-S02, UNIQUE |
| `membership_start_date` | дата начала контракта | `Reference59.Fld671::date` | `date` | нет | CONFIRMED physical type; sentinel `0001-01-01` observed and retained | CU-S03 |
| `membership_end_date` | дата окончания контракта | `Reference59.Fld672::date`; `end > start` | `date` | нет | BR-047: reused valid-membership predicate; full revalidation after filter change pending | CU-S03, target CHECK |
| `contract_end_month` | месяц когорты окончания | первый день месяца `membership_end_date` | `date` | нет | CONFIRMED requirement | month boundary |
| `membership_term_days` | срок действия в днях | `Reference59.Fld693::numeric` | `numeric` | да | CONFIRMED physical type `numeric(5,0)`; не подменяется разницей дат | CU-S03; RU-V04 |
| `active_calendar_months` | число затронутых календарных месяцев inclusive | `12 * (year(end)-year(start)) + month(end)-month(start) + 1` | `integer` | нет | BR-047 guarantees `>=1` after invalid intervals are excluded | CU-S03, target CHECK |
| `visit_count` | посещения, отнесённые к контракту | current-M `COUNT(*)` по `AccumRg7575` в dynamic BR-003 window; только для valid-membership domain BR-047 | `bigint` | нет | CONFIRMED BR-003/BR-018; 7-day CU-S01: 69,562 rows = technical keys = documents | CU-S01, CU-S03, CU-S04 |
| `usage_rate` | использование на один день срока | `visit_count / NULLIF(membership_term_days,0)` | `numeric` | да | CONFIRMED user formula | format and >100% |
| `average_monthly_visits` | среднемесячные посещения | `visit_count / NULLIF(active_calendar_months,0)` | `numeric` | да | CONFIRMED user formula | example and rounding |

## Source-фильтры

| Правило | Статус |
|---|---|
| `Document325.Fld4164 = GUID посещения` | CONFIRMED current query |
| тип клиента = переданный GUID `Клиент` | CONFIRMED current query |
| исключить ДРЦ и Управляющую компанию | CONFIRMED current query; ID pending |
| посещение внутри интервала контракта | Не добавлять filter: current M его не содержит, первый релиз сохраняет exact legacy domain |
| `AccumRg7575.Active` | Не добавлять filter; CU-S01 записывает observed inactive rows |
| `Document325.Posted/Marked` | Не добавлять filter; CU-S01 записывает observed states |
| тип полиморфного `AccumRg7575.Fld7578` = абонемент | full dynamic BR-003 CU-S01 passed; observed domain remains `08/0000003b` |
| `Reference59.Fld672::date <= Reference59.Fld671::date` | исключить по повторно используемому BR-047 valid-membership predicate; source 1С не изменяется |

## Не переносить

- ФИО, телефон, дату рождения и исходный ID клиента;
- исходные движения посещений;
- документ посещения;
- названия клубов как ключи;
- расчёты Renew и рекарринга из внешних выгрузок 1С;
- планы.

## Повторное использование

`mart.visit_client_day` не подходит напрямую: он намеренно не хранит контракт
и схлопывает события до клиент-дня. Расширение его ключом контракта увеличит
grain и объём для всех посещенческих отчётов.

Предпочтительный кандидат — отдельный компактный доменный набор метрик
контракта, который потенциально переиспользует «Управление продлением».
Физический объект утверждается только после разбора этого отчёта.

## Обновление

- компактный контрактный набор обновляется полным dynamic BR-003 horizon;
- runner вычисляет dynamic BR-003 horizon по Москве: текущий день допустим,
  будущие посещения блокируются (`CU-S04`);
- source-first runner записывает только производный набор в ограниченный
  временный файл, затем атомарно заменяет target внутри одной транзакции;
- watermark и инкрементальная семантика не проектируются;
- ежедневный SLA не заявляется до отдельного измеренного physical baseline.

## Проверки перед архитектурным решением

1. Уникальность `Reference59.ID` и `Reference59.Code`.
2. Тип полиморфного основания и кардинальность `visit → contract`.
3. `COUNT(*)` против `COUNT(DISTINCT Document325.ID)` и `SUM(Fld7585)`.
4. Состояния движения и документа.
5. Единица и допустимые значения `Fld693`.
6. Контрольный контракт, пересекающий границу года.
7. Контракт с заморозкой/разморозкой.
8. Размер целевой когорты и время source-side агрегации.

## Stage 2 evidence — SV-082 (2026-08-11)

Типы физически подтверждены: `Reference59.Fld693` — `numeric(5,0)`, а
`AccumRg7575.Fld7578` хранится как обязательные `Type`, `RTRef`, `RRRef`. На
bounded current-PBI пути 133 строк равны 133 technical keys и 133 документам;
виден один type-pair, но это не доказывает полный полиморфный домен.

В 100 cross-year контрактах 15 034 из 16 089 source-side событий полного
интервала лежат до 2026 года. Это сохраняется как BR-018 methodological note:
`COUNT(*)` и current fixed 2026 window воспроизводятся, а целевое полное окно
не включается без отдельного решения. В другой 100-contract выборке 25 сроков
неположительны, один интервал неположителен, срок не совпал с календарной
разницей ни в одной строке; не подменять `Fld693` вычислением по датам.

## Stage 3 technical-review evidence — CU-TR-001 / CU-TR-002 (2026-08-28)

В fresh `REPEATABLE READ, READ ONLY` sample `[2026-08-17, 2026-08-24)`
independent controls дали 69,562 legacy rows, столько же technical keys и
documents, 31,788 contract IDs, ноль duplicate contract-code groups и один
observed polymorphic pair `08/0000003b`. Наблюдаемые inactive/unposted/marked
rows равны нулю; они не превращены в новые фильтры. Два точных short plans
вернули 31,788 строк за 1,138.317 и 1,505.871 ms без disk/temp I/O.

После удаления неподтверждённой finalization-механики CU-TR-002 повторил
точный revised extract: 31,788 строк за 1,513.934 ms, planning 7.249 ms,
shared hit 1,060,822, без read/temp I/O. До admission CU-S01--CU-S03
выполнены на полном dynamic BR-003 horizon; initial DDL/DML/COPY, target
reconciliation и fresh-snapshot rerun приняты в CU-LOAD-001—008. См.
[execution evidence](../reports/contract_usage_stage3_product_admission_execution_2026-08-28.md).
