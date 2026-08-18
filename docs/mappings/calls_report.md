# Source-to-target mapping: «Отчет по обращениям»

Статус: `BUSINESS MAPPING COMPLETE / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED — SV-088, SV-098 / IMPLEMENTATION DEFERRED`.

Основание — переданные описание, Power Query, DAX и архивный PBIT
`Pbit_old/Отчет по обращениям.pbit` (SHA-256
`9c46cdc6847ec69617a1abf8eaa5cd0635777109d58ea162558391991bb1242f`), который не заменяет current SQL/M/DAX. SQL и объект витрины не
создаются. В этом mapping `CONFIRMED` означает подтверждённую текущую
логику, но не техническую валидность 1С-источников.

## Stage 2 evidence — SV-088, SV-098

Переиспользованы live read-only результаты SV-024—SV-034: physical PK
`_reference67._idrref`, many-to-one joins задачи и её dimension, а также
phone-row technical key и измеренная множественность. Поэтому current direct
phone join сохраняется по BR-018 и решению 2026-08-05; это не основание
схлопывать звонки до interaction. SV-098 добавляет bounded evidence по HTML,
first-followup/comment ordering и states; он не закрывает scope-фильтры,
visit event grain, Power BI reconciliation или refresh/re-run.

Полные результаты SV-098 зафиксированы в
[`server validation`](../source_metadata/server_validation_2026-08-14.md#sv-098--отчёт-по-обращениям-crm-core-and-comment-controls);
исправленный null-safe control, bounded first-followup path и CR-V05A — в
[`calls_report_global_review_2026-08-17.sql`](../source_metadata/validation_sql/calls_report_global_review_2026-08-17.sql).
CR-V05A подтверждает шесть тем и четыре из пяти документированных воронок.
Пользователь подтвердил, что source-наименование `Продажа клип карты
Рецепция` является нужной воронкой; CR-V05D зафиксировал её единственный
`Reference89._idrref = 99d7928e75e3805f11f0310981642c71`. По BR-023 source
filter использует этот ID, а не текст. Старое написание остаётся критичным
артефактом; статус реализации не меняется.

Архивный PBIT содержит отдельный scope страницы «Отработка обратной связи»:
все feedback interactions с 2025-01-01 без `Jivo` и без фиксированного
фильтра тем, воронок или кампаний. Это potential artifact; до сравнения с
current материалами он не применяется как source rule.

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
| `funnel_id` / `funnel_name` | `Reference106.Fld1191 → Reference89.Description`; для «Продажа клип-карт Рецепция» filter ID = `99d7928e75e3805f11f0310981642c71` | `UNKNOWN` / `text` | да | interaction | CONFIRMED — BR-023 / CR-V05D | V-05 remaining scopes |
| `department_id` / `department_name` | `Reference106.Fld8642 → Reference178.Description` | `UNKNOWN` / `text` | да | interaction | CONFIRMED current SQL | V-04 |
| `status_id` / `status_name` | `Reference67.Fld830`: `b78f16cfde0c1e1f4f7c0ae8d942393d` → «Выполнено»; `83b62b0bd3908a65448b72ca1ec17e94` → «Не выполнено»; `aef6c17befe0705047f834208813539a` → «Отменено» | `UNKNOWN` / `text` | да | interaction | VALIDATED current SQL + CR-V05F/G structure | exact values |
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

1. `PARTIALLY VALIDATED`: `Reference67 → InfoRg7146` имеет подтверждённую
   source-side множественность; `Reference67 → Reference137` и его
   deterministic aggregation остаются implementation blocker.
2. `CONFIRMED`: для отработки current «звонок» — любое последующее
   не-feedback CRM-взаимодействие, не только телефонный звонок (решение
   пользователя 2026-07-30).
3. `VALIDATION_PENDING`: техническая кардинальность связей Power BI и
   контрольные значения. Проектные связи зафиксированы в data contract;
   данные доступны не позднее 08:30 по Москве (`CONFIRMED`, BR-014).
4. `CONFIRMED`: BR-023 связывает документированную воронку
   «Продажа клип-карт Рецепция» с единственным physical ID
   `99d7928e75e3805f11f0310981642c71`. Текст не используется как filter;
   остающиеся V-05 scope controls проверяются отдельно.

## Refresh

Частота обновления — ежедневно (`CONFIRMED`, решение пользователя 2026-07-29).
Используется ежедневный bounded rebuild до подтверждения watermark; данные
должны быть доступны не позднее 08:30 по Москве (`CONFIRMED`, BR-014).
Историческое окно следует BR-003. Поздние изменения проверяются серверно по
BR-004 и не считаются доказанным инкрементом.
