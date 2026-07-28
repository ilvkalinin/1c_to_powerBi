# Source-to-target mapping: «Посещения Пушкинский»

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION DEFERRED`. Grain, формулы, состав КБ, категории и единое правило снимка 00:00 подтверждены.

## Логические наборы

### 1. Дневная структура клиентской базы

Предварительная гранулярность:

> отчётная дата × клуб Пушкинский.

| Целевое поле | Описание | Источник / преобразование | Тип | Статус |
|---|---|---|---|---|
| `report_date` | календарный день | календарь всех дней периода | `date` | CONFIRMED |
| `club_id` | Пушкинский | `Reference132.ID` | UNKNOWN | CONFIRMED source |
| `client_base_count` | distinct клиентов с действующим абонементом на 00:00 D | start < D и end >= D−1 | `integer`/`bigint` | CONFIRMED target |
| `visited_today_count` | distinct действующих членов, посетивших Пушкинский в D | membership set ∩ actual Pushkinsky visit set | `integer`/`bigint` | CONFIRMED BY DESIGN |
| `active_nonvisitor_count` | active membership ∩ visits `[D-30,D)` \ visits D | client sets на источнике | `integer`/`bigint` | CONFIRMED |
| `inactive_count` | `base - visited_today - active_nonvisitor` | арифметика готовых агрегатов | `integer`/`bigint` | CONFIRMED |

Client IDs используются только временно на VM-1 для пересечений и не сохраняются в этом агрегате.

### 2. Общий классифицированный client-day набор посещений

Кандидат на расширение общего mapping `docs/mappings/visits_fizkult.md`.

Предварительная гранулярность:

> дата посещения × фактический клуб × стабильный обезличенный клиент.

| Целевое поле | Описание | Источник / правило | Тип | Статус |
|---|---|---|---|---|
| `visit_date` | дата посещения | `AccumRg7575.Period` / `Document325` | `date` | CONFIRMED source |
| `club_id` | фактический клуб Пушкинский | `Document325.Fld4167` / `AccumRg7575.Fld7577` | UNKNOWN | CONFIRMED |
| `client_key` | стабильный обезличенный клиент | исходный client ID → утверждённое преобразование | UNKNOWN | implementation pending |
| `home_club_group` | Пушкинский / VIP / ДРЦ / другое | активный абонемент и `Reference132` на дату | UNKNOWN | business rule pending |
| `has_member_visit` | посещение членом Пушкинского | фактический Пушкинский + active home membership | `boolean` | DAX / interval pending |
| `has_coupon` | посещение по купону | общий coupon mapping | `boolean` | source confirmed / DAX pending |
| `has_paid_service` | ДПФУ | правила `Посещения проверка ДПФУ` | `boolean` | CONFIRMED |
| `has_guest_visit` | гостевой визит | услуга содержит гостевой признак, кроме кафе | `boolean` | current rule / confirmation pending |
| `has_vip_visit` | основной клуб VIP | active membership VIP + actual Пушкинский | `boolean` | current rule |
| `has_drc_visit` | основной клуб ДРЦ, кроме Продлёнки и Умняшек | active membership ДРЦ + actual Пушкинский + исключение двух категорий | `boolean` | CONFIRMED |
| `has_after_school_visit` | Продлёнка | услуга по подстроке | `boolean` | current rule |
| `has_umnyashki_visit` | Умняшки | услуга по подстроке | `boolean` | current rule |

### 3. Дневной агрегат ГП

Переиспользовать общий набор ГП:

> дата события × клуб.

`group_program_visit_count = SUM(InfoRg8675.Fld8677)`.

## Не переносить на VM-2

- ФИО и исходные коды клиентов;
- сырые абонементы;
- сырые движения посещений и продаж;
- названия услуг после классификации;
- исходные документы и GUID-константы.

## Блокеры

- состояния источников и кардинальности;
- способ стабильного обезличивания клиента;
- контрольные значения.

## Общие физические объекты

Не создавать отдельную таблицу посещений Пушкинского. Использовать проектное решение `docs/adr/0003-shared-visits-domain.md`:

- `mart.visit_client_day` — общий client-day факт для Физкульт и Пушкинского;
- `mart.club_day_metrics` — общий дневной агрегат `дата × клуб`, объединяющий ГП и состояние КБ Пушкинского.

В `mart.visit_client_day` добавляются только подтверждённые флаги Пушкинского; сырые услуги и документы не переносятся.

## Refresh

- один раз в день;
- только подтверждённый период истории;
- кандидат на регулярный пересчёт — общее окно поздних изменений около двух месяцев;
- точный watermark и механизм загрузки отложены до технической проверки.
