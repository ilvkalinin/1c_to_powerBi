# Source-to-target mapping: общий CRM core

Статус: `ADMISSION PREPARATION COMPLETE / IMPLEMENTATION NOT AUTHORIZED`.

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
`Reference67.ID`. Они разрешены только в report-specific extraction с
профилированием cardinality и детерминированной агрегацией/сохранением текущей
мультипликативности.

## Candidate core columns

`text` для protected source ID означает будущую явную стабильную serialisation
(например, hex); её точный physical type и null-profile ещё не проверены на
сервере и потому имеют `VALIDATION_PENDING`. PII и HTML не становятся
публичными полями core: способ их хранения и выдачи только из нужных views —
отдельный security design до DDL.

| Core column | Source / transformation | Type / NULL | Grain | Status | Required validation |
|---|---|---|---|---|---|
| `interaction_id` | `Reference67.ID`; PBIT sales/guest выводят `encode(...,'hex')` | `text`, not null | interaction | CONFIRMED current | source PK = target PK |
| `task_id` | `Reference67.OwnerID → Reference106.ID` | `text`, null pending | interaction | CONFIRMED source / VALIDATION_PENDING representation | orphan and null profile |
| `created_at` | `Reference67.Fld823` | `timestamp`, null pending | interaction | CONFIRMED current / VALIDATION_PENDING physical type | type, sentinel and timezone |
| `started_at`, `ended_at`, `planned_at` | `Reference67.Fld820`, `Fld821`, `Fld822` | `timestamp`, nullable | interaction | CONFIRMED current / VALIDATION_PENDING physical type | sentinel, null and ordering profile |
| `event_type_id` | `Reference67.Fld831` | `text`, nullable | interaction | CONFIRMED source | value coverage and stable encoding |
| `state_id`, `status_id` | `Reference67.Fld829`, `Fld830` | `text`, nullable | interaction | CONFIRMED source | value coverage; preserve unknown values |
| `executor_id`, `cancellation_reason_id` | `Reference67.Fld824`, `Fld828` | `text`, nullable | interaction | CONFIRMED source | left-join coverage / stable encoding |
| `client_id`, `club_id`, `funnel_id`, `campaign_id`, `channel_id` | `Reference106.Fld1196`, `Fld1195`, `Fld1191`, `Fld1197`, `Fld1194` | `text`, nullable | interaction | CONFIRMED current source / VALIDATION_PENDING representation | task-side null/orphan profile |
| `tenure_type_id`, `client_status_id` | `Reference106.Fld1190`, `Fld1204` | `text`, nullable | interaction | CONFIRMED current source | mapping coverage and unknown values |
| `feedback_topic_id`, `department_id`, `position_id`, `regulated_interaction_id` | `Reference106.Fld8643`, `Fld8642`, `Fld1199`, `Fld1202` | `text`, nullable | interaction | CONFIRMED feedback consumer | source availability and cardinality |
| non-PII display labels for the above IDs | existing reference descriptions used by the three PBITs | `text`, nullable | interaction | ASSUMPTION — storage versus source-side resolution | choose storage/grant model before DDL |
| client PII (`code`, name, phone), interaction name, HTML/comment | `Reference141X1`, `Reference67.Description`, `Reference137` | view-only, nullable | report detail | CONFIRMED consumer / DECISION_REQUIRED security representation | BR-017 grants and no PII exposure from core |

Current fixed classifications (event/status/state/funnel/campaign) are
report-view rules. Core preserves their IDs and timestamps; it does not turn a
single report's filter or display bucket into a global row filter.

## Reuse boundary

| Consumer | Reuse of core | Remains in report view |
|---|---|---|
| `v_sales_interaction` | interaction/task/CRM classification | direct phone-row semantics, sales funnels/Jivo rule, employment `EXISTS`, durations and Power BI measures |
| `v_feedback_interaction` | interaction/task/feedback attributes | feedback-type scope, HTML normalization, first follow-up, worked/response calculations and visit denominator |
| `v_guest_tour` | interaction/task/client/club/state/status | meeting/funnel/status scope, report date, ACCUNIQ and purchase outcomes |

## PBIT reconciliation — resolved report-view rules

| Consumer | Template evidence | Consequence |
|---|---|---|
| Sales | `Взаимодействия2025/2026` directly joins `InfoRg7146`; after the personnel filter it applies `Table.Distinct` on business columns and includes `Ведущий менеджер` in addition to two documented roles. | `RESOLVED`: include the third role; preserve each distinct technical phone row under user decision 2026-08-05. `Distinct` may remove only a true technical duplicate. |
| Feedback | `ОС со звонками` selects feedback from 2025-01-01 to current date, excludes `Jivo` in interaction name, joins phone/HTML, then groups without `Reference67.ID`; first follow-up is minimum non-feedback interaction for `client code × task code` after feedback creation. | `RESOLVED`: core remains one `interaction_id`; first-release compatibility view preserves final PBIT business-grouping without it, under BR-018 and the approved PBIT. |
| Guest tour | `ТурыВсе` directly joins `InfoRg7146`, filters meeting + `Продажа клубной карты`, computes report date from `Fld820` or `Fld822`, and the final `Туры` keeps only `Закрыто/Выполнено` or `Запланировано/Не выполнено`. | `RESOLVED`: view preserves PBIT phone-row multiplicity and `report_date`; no phone row alters core grain. Hidden technical key and sentinel profiling remain physical validation. |

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
5. Prove deterministic tie-break for comments and follow-up (`timestamp` plus
   physical technical key), PII grants, rerun equality and timing separately.
