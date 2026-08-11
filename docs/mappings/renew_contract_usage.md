# Source-to-target mapping: использование контрактов для %Renew

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-082; Stage 3 deferred`.
SQL и физические объекты не создаются.

## Гранулярность

> один контракт.

Технический ключ:

> `contract_id = Reference59.ID`.

`contract_code` сохраняется только как ключ связи с существующей выгрузкой 1С,
пока та не начнёт передавать бинарный ID контракта.

## Mapping

| Целевая колонка | Бизнес-описание | Источник / преобразование | PostgreSQL тип | NULL | Статус / доказательство | Проверка |
|---|---|---|---|---|---|---|
| `contract_id` | стабильный ID контракта | `Reference59.ID` | UNKNOWN | нет | CONFIRMED metadata | уникальность |
| `contract_code` | код для связи с существующей выгрузкой 1С | `Reference59.Code::text` | `text` | нет | CONFIRMED current integration | уникальность и пробелы |
| `membership_start_date` | дата начала контракта | `Reference59.Fld671::date` | `date` | нет | CONFIRMED metadata | sentinel и timezone |
| `membership_end_date` | дата окончания контракта | `Reference59.Fld672::date` | `date` | нет | CONFIRMED metadata | end >= start |
| `contract_end_month` | месяц когорты окончания | первый день месяца `membership_end_date` | `date` | нет | CONFIRMED requirement | month boundary |
| `membership_term_days` | срок действия в днях | `Reference59.Fld693` | UNKNOWN numeric | да | CONFIRMED business field / physical type pending | единица, zero, freeze |
| `active_calendar_months` | число затронутых календарных месяцев inclusive | `12 * (year(end)-year(start)) + month(end)-month(start) + 1` | `integer` | нет | CONFIRMED user rule | пример 13 |
| `visit_count` | посещения, отнесённые к контракту | текущий кандидат `COUNT(*)` по `AccumRg7575` внутри интервала контракта | `bigint` | нет | CONFIRMED current rule / semantic validation pending | rows vs documents vs quantity |
| `usage_rate` | использование на один день срока | `visit_count / NULLIF(membership_term_days,0)` | `numeric` | да | CONFIRMED user formula | format and >100% |
| `average_monthly_visits` | среднемесячные посещения | `visit_count / NULLIF(active_calendar_months,0)` | `numeric` | да | CONFIRMED user formula | example and rounding |
| `is_finalized` | контракт относится к закрытому неизменяемому месяцу | `true` после фиксации его месяца окончания | `boolean` | нет | CONFIRMED user process / BY DESIGN | один finalization |
| `finalized_month` | закрытый месяц, в котором зафиксированы метрики | первый день закрытого месяца; `NULL` для mutable-когорты | `date` | да | CONFIRMED BY DESIGN | соответствует end month |

## Source-фильтры

| Правило | Статус |
|---|---|
| `Document325.Fld4164 = GUID посещения` | CONFIRMED current query |
| тип клиента = переданный GUID `Клиент` | CONFIRMED current query |
| исключить ДРЦ и Управляющую компанию | CONFIRMED current query; ID pending |
| посещение внутри интервала контракта | CONFIRMED target rule |
| `AccumRg7575.Active` | UNKNOWN |
| `Document325.Posted/Marked` | UNKNOWN |
| тип полиморфного `AccumRg7575.Fld7578` = абонемент | BLOCKER before SQL |

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

## Снимки и обновление

- закрытый месяц сохраняется отдельным неизменяемым Excel-снимком;
- PostgreSQL не хранит копии Excel, но сохраняет одну финальную строку метрик
  использования на контракт, чтобы исторический снимок продолжал находить её;
- компактный контрактный набор обновляется ежедневно;
- строки закрытых месяцев не пересчитываются;
- текущие и будущие окончания образуют mutable-секцию и атомарно заменяются;
- бизнес-инвариант-кандидат: один контракт фиксируется только в одном закрытом
  месяце и после фиксации не переносится в другую когорту.

## Проверки перед архитектурным решением

1. Уникальность `Reference59.ID` и `Reference59.Code`.
2. Тип полиморфного основания и кардинальность `visit → contract`.
3. `COUNT(*)` против `COUNT(DISTINCT Document325.ID)` и `SUM(Fld7585)`.
4. Состояния движения и документа.
5. Единица и допустимые значения `Fld693`.
6. Контрольный контракт, пересекающий границу года.
7. Контракт с заморозкой/разморозкой.
8. Размер целевой когорты и время source-side агрегации.
9. Один контракт не появляется в двух закрытых Excel-снимках.
10. Порядок финального обновления usage и сохранения Excel на границе месяца.

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
