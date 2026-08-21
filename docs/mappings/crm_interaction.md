# Source-to-target mapping: общий CRM core

Статус: `REPLANNING UNDER BR-032 / NO FURTHER DML AUTHORIZED`.

Это evidence-based mapping будущего `mart.crm_interaction`, а не DDL и не
разрешение на создание объекта. Core grain — ровно одно CRM-взаимодействие
`Reference67.ID`; логический ключ `interaction_id`. Подтверждённые consumers:
`mart.v_sales_interaction`, `mart.v_feedback_interaction` и
`mart.v_guest_tour` (ADR-0016).

## Evidence и границы

- [Загрузка ОП](sales_interactions.md), [Отчёт по обращениям](calls_report.md)
  и [Новички и гостевые визиты](newcomer_guest_visits.md) — source mapping и
  Stage 2 evidence.
- ADR-0016 — reuse decision и core grain.
- PBIT сверены read-only по явному разрешению пользователя 2026-08-21:
  `Pbit_old/Загрузка ОП.pbit` SHA-256
  `0bd13b545645246cb8498e7ac82f5d7b13ee436137be67197d579cdb16d92bfd`,
  `Pbit_old/Отчет по обращениям.pbit` SHA-256
  `9c46cdc6847ec69617a1abf8eaa5cd0635777109d58ea162558391991bb1242f`,
  `Pbit_old/Новички и гостевые визиты.pbit` SHA-256
  `3d54a392bec0d3feed21f998c91bf4607886ca101eac7b0adc94d6bbce180796`.

Телефонные строки `InfoRg7146`, HTML `Reference137` и кадровые интервалы не
присоединяются к core как обычные detail joins: каждый может размножить одну
`Reference67.ID`. Read-only control 2026-08-21 подтвердил, что для сохранения
current phone-row и comment semantics нужны две малые дочерние таблицы, а не
join в core: `mart.crm_interaction_phone` и
`mart.crm_interaction_comment`. Это часть reviewed architecture, не DDL.

## Candidate core columns

`text` для protected source ID означает `encode(source_id, 'hex')`. Read-only
control 2026-08-21 подтвердил `bytea` для проверенных ID и `timestamp without
time zone` для CRM timestamps; core July-2026 содержит 342 824 interaction и
0 строк без задачи. PII и HTML не становятся публичными полями core: хранение
дочерних данных и выдача только из нужных views требуют `REVOKE ... FROM
PUBLIC` и отдельного named BI role/grant в implementation package.

| Core column | Source / transformation | Type / NULL | Grain | Status | Required validation |
|---|---|---|---|---|---|
| `interaction_id` | `encode(Reference67.ID, 'hex')`; PBIT sales/guest use the same serialisation | `text`, not null | interaction | CONFIRMED current + physical | source PK = target PK |
| `task_id` | `encode(Reference67.OwnerID, 'hex') → Reference106.ID` | `text`, not null | interaction | CONFIRMED source + July-2026 orphan profile | full rebuild reconciliation |
| `task_code`, `task_description` | `Reference106.Code`, `Fld1200` | `text`, not null | interaction | CONFIRMED current PBIT + physical 2026-08-21 (`mvarchar(9)`, `mvarchar(1000)`) | feedback PBIT grouping |
| `created_at` | `Reference67.Fld823` | `timestamp without time zone`, not null | interaction | CONFIRMED current + physical | sentinel and timezone are source-preserved |
| `started_at`, `ended_at`, `planned_at` | `Reference67.Fld820`, `Fld821`, `Fld822` | `timestamp without time zone`, not null | interaction | CONFIRMED current + physical | source sentinel profile: 228 834 / 232 344 / 124 221 in July-2026 |
| `event_type_id` | `Reference67.Fld831` | `text`, nullable | interaction | CONFIRMED source | value coverage and stable encoding |
| `state_id`, `status_id` | `Reference67.Fld829`, `Fld830` | `text`, nullable | interaction | CONFIRMED source | value coverage; preserve unknown values |
| `executor_id`, `cancellation_reason_id` | `Reference67.Fld824`, `Fld828` | `text`, nullable | interaction | CONFIRMED source | left-join coverage / stable encoding |
| `client_id`, `club_id`, `funnel_id`, `campaign_id`, `channel_id` | `Reference106.Fld1196`, `Fld1195`, `Fld1191`, `Fld1197`, `Fld1194` | `text`, nullable | interaction | CONFIRMED current source / VALIDATION_PENDING representation | task-side null/orphan profile |
| `tenure_type_id`, `client_status_id` | `Reference106.Fld1190`, `Fld1204` | `text`, not null | interaction | CONFIRMED current + physical | mapping coverage and unknown values |
| `feedback_topic_id`, `department_id`, `position_id`, `regulated_interaction_id` | `Reference106.Fld8643`, `Fld8642`, `Fld1199`, `Fld1202` | `text`, nullable | interaction | CONFIRMED feedback consumer | source availability and cardinality |
| `feedback_theme` | `InfoRg5810.Fld5811 = Reference106.ID → Reference110.Fld5813.Description` | `text`, nullable | interaction | CONFIRMED current PBIT + physical 2026-08-21 | feedback PBIT grouping |
| `campaign_code` | `Reference106.Fld1197 → Reference145.Code` | `text`, nullable | interaction | CONFIRMED current PBIT + physical 2026-08-21 (`mvarchar(9)`) | feedback PBIT grouping |
| non-PII display labels for the above IDs | existing reference descriptions used by the three PBITs | `text`, nullable | interaction | ASSUMPTION — storage versus source-side resolution | choose storage/grant model before DDL |
| client PII (`code`, name, phone), interaction name, HTML/comment | `Reference141X1`, `Reference67.Description`, `Reference137` | view-only, nullable | report detail | CONFIRMED consumer / DECISION_REQUIRED named BI role | BR-017 grants and no PII exposure from core |

До решения BR-032 fixed classifications (event/status/state/funnel/campaign)
сохранялись как широкие core-поля, а report filters оставались во views. Это
решение заменено: новая загрузка обязана передавать из VM-1 только доказанный
union трёх report scopes и только нужные им поля. Общий объект допустим, только
если этот union сохраняет grain и семантику каждого consumer; иначе создаются
отдельные узкие факты.

## Reuse boundary

| Consumer | Reuse of core | Remains in report view |
|---|---|---|
| `v_sales_interaction` | interaction/task/CRM classification | direct phone-row semantics, sales funnels/Jivo rule, employment `EXISTS`, durations and Power BI measures |
| `v_feedback_interaction` | interaction/task/feedback attributes | feedback-type scope, HTML normalization, first follow-up, worked/response calculations and visit denominator |
| `v_guest_tour` | interaction/task/client/club/state/status and phone child | meeting/funnel/status scope and report date; ACCUNIQ and purchase outcomes remain in Power BI by BR-031 |

## BR-032 optimisation requirement

Пользователь 2026-08-21 зафиксировал, что цель — оптимизировать Power BI, а
не перенести его широкие промежуточные выгрузки в PostgreSQL. Перед следующей
загрузкой необходимо доказать для каждого из трёх consumers минимальные:

1. source predicates и роль даты;
2. строки, нужные как detail либо как input к подтверждённой агрегации;
3. итоговые поля, без которых Power BI не сможет посчитать свои меры и срезы;
4. допустимый общий union и все преобразования, выполняемые source-side на
   VM-1.

Текущий reviewed plan, который переносит все `Reference67` за BR-003 по
`created_at`, этому требованию не соответствует и не выполняется повторно.

## PBIT reconciliation — resolved report-view rules

| Consumer | Template evidence | Consequence |
|---|---|---|
| Sales | `Взаимодействия2025/2026` directly joins `InfoRg7146`; after the personnel filter it applies `Table.Distinct` on business columns and includes `Ведущий менеджер` in addition to two documented roles. | `RESOLVED`: include the third role; preserve each distinct technical phone row under user decision 2026-08-05. `Distinct` may remove only a true technical duplicate. |
| Feedback | `ОС со звонками` selects feedback from 2025-01-01 to current date, excludes `Jivo` in interaction name, joins phone/HTML, then groups without `Reference67.ID`; first follow-up is minimum non-feedback interaction for `client code × task code` after feedback creation. | `RESOLVED`: core remains one `interaction_id`; first-release compatibility view preserves final PBIT business-grouping without it, under BR-018 and the approved PBIT. |
| Guest tour | `ТурыВсе` directly joins `InfoRg7146`, filters meeting + `Продажа клубной карты`, computes report date from `Fld820` or `Fld822`, and the final `Туры` keeps only `Закрыто/Выполнено` or `Запланировано/Не выполнено`. | `RESOLVED`: view preserves PBIT phone-row multiplicity and `report_date`; no phone row alters core grain. Funnel key `99a9ebb169a4e2a611eecbf18a73ffa6` was read-only confirmed 2026-08-21 as the sole `Продажа клубной карты` key. |

The Jivo marketing-name condition in the feedback template is in a `LEFT JOIN`:
it nulls that label rather than excluding the interaction. The documented
source-scope statement therefore remains unchanged; implementation must test
this effect explicitly.

## Required acceptance controls before implementation

1. `Reference67.ID` has a one-to-one target row in core; no task or optional
   dimension join changes its count.
2. Profile and preserve marked/archive/sentinel behaviour; do not add a new
   state filter.
3. Measure phone, HTML and employment cardinalities separately; prove the
   chosen per-view aggregation or multiplicity against each PBIT.
4. Reconcile each report view to its PBIT current result for a fixed period,
   including PBIT-only `Distinct`/grouping, filters, dates and null behaviour.
5. Use deterministic ordering for comments and follow-up: timestamp plus
   physical technical key. On 2026-08-21, bounded feedback controls observed
   1 earliest-follow-up tie; full July control found no same-interaction
   comment timestamp tie. The secondary comment key remains an explicit
   reproducibility safeguard.
6. Resolve guest outcome selection: current PBIT preserves 8 equal latest
   ACCUNIQ timestamps and 128 duplicate `client × date` rows; it also lacks a
   contract-ID order after the minimum conversion lag. A production SQL
   tie-break or a deliberate legacy-multiplicity exception is required.
