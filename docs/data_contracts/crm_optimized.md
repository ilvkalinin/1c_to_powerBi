# Data contract: compact CRM products under BR-032/BR-033

Статус: `DESIGNED / REVIEWED SQL PENDING / NO DDL OR DML`.

## Общая граница

VM-1 готовит данные в `REPEATABLE READ READ ONLY`; VM-2 получает только
готовые compact facts. Один shared interaction core используется для sales и
guest tour, потому что у них общий event/key `Reference67.ID`. Feedback не
присоединяется к этому core как raw detail: его итоговый business grain и
comment logic несовместимы и строятся source-side отдельным компактным фактом.

Для initial CRM load верхняя граница — начало текущего дня (`current_date`),
а не 1 января следующего года из общего BR-003: будущие запланированные
события не являются необходимым объёмом передачи (BR-034).

| Target object | Grain / key | Consumer | Source-side preparation |
|---|---|---|---|
| `mart.crm_interaction` | one `interaction_id` | sales, guest tour | only union sales/guest scope; task/client/classification joins and reusable derived fields |
| `mart.crm_interaction_phone` | `(interaction_id, phone_reference_id, phone_event_id)` | sales, guest tour | only phone rows of the compact core; `phone_at`, answered flag and technical key are prepared before COPY |
| `mart.feedback_interaction` | final feedback business group, without interaction ID | calls report | feedback predicate, Jivo exclusion, HTML→text, date/status mappings, first non-feedback follow-up, comment aggregation and worked fields |
| `mart.club_day_metrics` | `(event_date, club_id)` | calls report and future club-day consumers | `AccumRg7575` visit denominator aggregated source-side; no client/contract raw rows |

`mart.v_sales_interaction`, `mart.v_feedback_interaction` and
`mart.v_guest_tour` are thin stable Power BI contracts over those facts. They
may make only local projections/join the scoped phone child; no view reads
VM-1 or repeats a source transformation.

## Compact shared core

`mart.crm_interaction` receives only rows in the union below, bounded by
BR-003 according to the role of each report date:

1. sales: three approved funnels, service-Jivo exclusion and confirmed
   source-side employment `EXISTS`; an interaction is retained only when its
   effective interaction date or its planned date is in the horizon;
2. guest tour: meeting in `Продажа клубной карты`, one of the two approved
   state/status pairs, and `report_date` in the horizon.

Required shared fields are the stable interaction/task/client/club/funnel IDs,
their approved display attributes, created/start/end/planned timestamps,
event/state/status/cancellation classifications, sales personnel flag and the
guest `report_date`/`tour_kind` fields. PII is limited to the confirmed
sales/tour detail fields under BR-017. Marked/archive fields, raw HTML,
unscoped phone rows, employment history and all interactions outside the
union are not transferred.

The task-side client, club, funnel, campaign and channel references are
nullable in the compact contract because their current-PBIT lookups are left
joins. A missing marketing campaign was observed during initial COPY; it is a
valid source row, not a reason to exclude the interaction.

For sales `network_name` is computed source-side exactly as the checked PBIT:
`club_name IN ('Пушкинский', 'Пушкинский VIP') → 'Пушкинский'`, otherwise
`'Физкульт'`. This is evidence from `Загрузка ОП.pbit`, not an inferred club
hierarchy.

## Feedback compact fact

`mart.feedback_interaction` includes all feedback interactions in the approved
calls scope: feedback type, created date in BR-003 and source interaction name
not containing `Jivo`. It keeps the final business grouping specified by the
checked PBIT, not `Reference67.ID`.

The checked template also groups and returns the interaction name. Therefore
`interaction_name` is retained in this compact fact; it adds no source event
or raw child detail.

Technical interaction, task, client and reference IDs are intentionally not
present in this fact: the checked template neither returns nor groups by them.
Keeping them would both enlarge the transfer and risk splitting an existing
PBIT business group where display codes/names coincide.

VM-1 computes normalized comment text with raw-text fallback, distinct comment
aggregation, earliest post-creation comment update, earliest later
non-feedback interaction by `client_code × task_code`, `worked_at`,
`worked_flag`, `response_minutes`, `resolution_days` and the approved status,
tenure and display mappings. It transfers no raw comment HTML, phone rows or
unrelated follow-up interactions.

## Daily visit denominator

`mart.visit_client_day` cannot be reused for the calls denominator: it has
client-day boolean grain, while the calls report needs additive count of
contract references. `mart.club_day_metrics` receives only
`event_date`, `club_id`, `club_name` and `visit_event_count`, aggregated in
VM-1 from the confirmed `AccumRg7575 → Document325` path. This is a compact
generic day × actual-club fact and is available for reuse by later reports.

## Acceptance boundary

The revised runner must reconcile source COPY rows and target rows for each
fact, keys/nulls/public privileges, feedback grouping and the known visit
denominator. A rerun measures full rebuild only; it does not claim a daily
incremental SLA. Guest ACCUNIQ/contract outcomes remain Power BI-only by
BR-031.
