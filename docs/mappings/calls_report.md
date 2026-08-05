# Source-to-target mapping: «Отчет по обращениям»

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION DEFERRED`.

Основание — переданные описание, Power Query и DAX. SQL и объект витрины не
создаются. В этом mapping `CONFIRMED` означает подтверждённую текущую
логику, но не техническую валидность 1С-источников.

## Reuse review

| Вариант | Вывод | Доказательство |
|---|---|---|
| `REUSE` | Неприменим для готового продукта. `mart.visit_client_day` не хранит количество посещений; текущая мера требует сумму событий. | grain `date × club × client` с boolean против count visits |
| `EXTEND` | Кандидат для CRM-core interaction: расширить логический факт «взаимодействия отдела продаж» атрибутами обратной связи и product-specific view/фильтрами. | одинаковый source event `Reference67.ID` и task `Reference106.ID`; [sales mapping](sales_interactions.md) |
| `NEW` | Кандидат отдельного дневного знаменателя `дата × фактический клуб` для количества посещений. Физический объект не выбран. | distinct client-day не воспроизводит `SUM(Количество посещений)` |

Архитектурное решение: `DESIGNED — ADR-0016`. Используется общий
`mart.crm_interaction`, но отбор «Загрузка ОП» не копируется: feedback-логика
реализуется в `mart.v_feedback_interaction`. Дневной знаменатель расширяет
`mart.club_day_metrics` на том же grain.

## Гранулярность

Кандидат факта обратной связи:

> одна строка на `Reference67.ID`, где interaction type = «Обратная связь».

Ключ `feedback_interaction_id = interaction_id`. HTML, телефония и связанные
звонки имеют неизвестную кардинальность и должны быть предварительно
нормализованы до одной строки/детерминированного агрегата.

Кандидат знаменателя посещений:

> дата фактического посещения × клуб фактического посещения.

## Целевые поля обратной связи

| Целевая колонка | Описание / источник и преобразование | Тип | NULL | Grain | Статус и доказательство | Проверка |
|---|---|---|---|---|---|---|
| `feedback_interaction_id` | `Reference67.ID`; не выводить GUID в Power BI | `UNKNOWN` | нет | interaction | CONFIRMED source | V-02 |
| `task_id` | `Reference67.OwnerID = Reference106.ID` | `UNKNOWN` | нет | interaction | CONFIRMED current SQL | V-02 orphan tasks |
| `created_at` | `Reference67.Fld823` | `timestamp` `UNKNOWN` | нет | interaction | CONFIRMED current SQL | V-01 type/timezone |
| `created_date` | `created_at::date` для календаря | `date` | нет | interaction | CONFIRMED need | V-01 |
| `started_at` | `Reference67.Fld820` | `timestamp` `UNKNOWN` | да | interaction | CONFIRMED current SQL | V-01 |
| `ended_at` | `Reference67.Fld821` | `timestamp` `UNKNOWN` | да | interaction | CONFIRMED current SQL | V-01 |
| `planned_at` | `Reference67.Fld822` | `timestamp` `UNKNOWN` | да | interaction | CONFIRMED current SQL | V-01 |
| `resolution_days` | календарная разница `ended_at::date - created_at::date`; не использовать `planned_at` | `integer` | да | interaction | CONFIRMED — решение пользователя 2026-07-29 | V-01 type/null/negative |
| `resolution_bucket` | `≤1` = `01 День`; `<4` = `02-03 Дня`; `<8` = `04-07 Дней`; иначе `Больше 7 дней`; `Не выполнена` выводится из статуса в Power BI | `text` | да | interaction | CONFIRMED current grouping + user decision о датах | V-10 |
| `feedback_topic_id` | `Reference106.Fld8643` | `UNKNOWN` | да | interaction | CONFIRMED current SQL | V-05 values |
| `feedback_topic_name` | `Reference8628.Description` | `text` | да | interaction | CONFIRMED current SQL | V-05 six-topic scope |
| `club_id` | `Reference106.Fld1195` | `UNKNOWN` | да | interaction | CONFIRMED current SQL | V-04 FK |
| `club_name` | `Reference132.Description` | `text` | да | interaction | CONFIRMED need | V-04 |
| `funnel_id` / `funnel_name` | `Reference106.Fld1191 → Reference89.Description` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-05 five funnels |
| `department_id` / `department_name` | `Reference106.Fld8642 → Reference178.Description` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `status_id` / `status_name` | `Reference67.Fld830`; current GUID mapping: выполнено / не выполнено / отменено | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-05 all values |
| `state_id` / `state_name` | `Reference67.Fld829 → Reference224.Description` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `executor_id` / `executor_name` | `Reference67.Fld824 → Reference225.Description` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `position_id` / `position_name` | `Reference106.Fld1199 → Reference101.Description` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `client_id` / `client_code` / `client_name` | `Reference106.Fld1196 → Reference141X1.ID/Code/Description` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL; detail available to every report viewer by user decision 2026-07-29 | V-02, permissions/RLS |
| `client_phone` | `Reference141X1.Fld1531` | `text` | да | interaction | CONFIRMED current SQL; detail available to every report viewer by user decision 2026-07-29 | V-01, permissions/RLS |
| `tenure_type` | `Reference106.Fld1190`; current GUID mapping New/Ex/Renew | `text` | да | interaction | CONFIRMED current SQL | V-05 |
| `campaign_id` / `campaign_name` | `Reference106.Fld1197 → Reference145` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-05 Jivo rule |
| `channel_name` | `Reference106.Fld1194 → Reference122.Description` | `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `regulated_interaction_name` | `Reference106.Fld1202 → Reference212.Description` | `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `cancellation_reason_name` | `Reference67.Fld828 → Reference202.Description` | `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `comment_text` | normalised `Reference137.Fld1464`, fallback raw HTML | `text` | да | interaction | CONFIRMED current transformation; content available to every report viewer by user decision 2026-07-29 | V-03, V-07, permissions/RLS |
| `comment_updated_at` | earliest `Reference137.Fld1463 > created_at` | `timestamp` `UNKNOWN` | да | interaction | CONFIRMED current transformation | V-03, V-07 |
| `first_followup_at` | первое последующее CRM-взаимодействие после обратной связи в той же паре task × client, кроме interaction типа «Обратная связь» | `timestamp` `UNKNOWN` | да | interaction | CONFIRMED — сохранить current SQL по решению пользователя 2026-07-30 | V-06 |
| `worked_at` | `COALESCE(first_followup_at, comment_updated_at)` | `timestamp` `UNKNOWN` | да | interaction | CONFIRMED current SQL | V-07 |
| `worked_flag` | `worked_at IS NOT NULL` | `boolean` | нет | interaction | CONFIRMED current DAX | V-10 |
| `response_minutes` | `(worked_at - created_at) / 60`; применять в медиане для всех строк с `worked_at`, включая изменение комментария без звонка | `numeric` | да | interaction | CONFIRMED — решение пользователя 2026-07-29 | V-07 negative/ties, V-10 |
| `feedback_count` | Не материализируется как `1` на interaction: текущая мера считает distinct пары `comment_text × client_code`; воспроизводится DAX-мерой на полях факта. | `smallint` | не применимо | interaction | CONFIRMED — current DAX | V-10 |

## Целевые поля знаменателя посещений

| Целевая колонка | Описание / источник и преобразование | Тип | NULL | Grain | Статус и доказательство | Проверка |
|---|---|---|---|---|---|---|
| `visit_date` | `AccumRg7575.Period::date` | `date` | нет | date × actual club | CONFIRMED current SQL | V-01 boundaries |
| `actual_club_id` / `actual_club_name` | `Document325.Fld4167 → Reference132` | `UNKNOWN` / `text` | нет | date × actual club | CONFIRMED current SQL | V-08 |
| `visit_count` | count `AccumRg7575.Fld7578` after confirmed filters and deduplication | `bigint` | нет | date × actual club | CONFIRMED current measure | V-08 source grain |

## Не переносить без подтверждённого потребителя

- исходные HTML, GUID и технические ID в пользовательскую модель;
- полную копию CRM-справочников, телефонии или регистра посещений;
- основной клуб доступа и контракт из набора посещений: в текущем отчёте они
  не являются разрезами знаменателя;
- client PII вне подтверждённой детальной таблицы; внутри неё детализация
  доступна всем пользователям отчёта.

## Блокеры и риски

1. `VALIDATION_PENDING — implementation blocker`: техническая кардинальность `Reference67 → InfoRg7146` /
   `Reference137`; без неё строка interaction не доказана.
2. `CONFIRMED`: для отработки current «звонок» — любое последующее
   не-feedback CRM-взаимодействие, не только телефонный звонок (решение
   пользователя 2026-07-30).
3. `VALIDATION_PENDING`: техническая кардинальность связей Power BI и
   контрольные значения. Проектные связи зафиксированы в data contract;
   данные доступны не позднее 08:30 по Москве (`CONFIRMED`, BR-014).

## Refresh

Частота обновления — ежедневно (`CONFIRMED`, решение пользователя 2026-07-29).
Используется ежедневный bounded rebuild до подтверждения watermark; данные
должны быть доступны не позднее 08:30 по Москве (`CONFIRMED`, BR-014).
Историческое окно следует BR-003. Поздние изменения проверяются серверно по
BR-004 и не считаются доказанным инкрементом.
