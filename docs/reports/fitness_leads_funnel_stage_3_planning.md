# Stage-3 planning: «Воронка лиды фитнес»

Статус: `COMPATIBILITY RESOLVED — runnable admission must design one task fact plus a separate service bridge`.

## Reuse review after marketing-funnel implementation

| Candidate | Grain / scope | Decision |
|---|---|---|
| `mart.marketing_funnel_task` | one CRM task, but only funnel «Продажа клубной карты» | `NOT_APPLICABLE` for physical reuse: the four fitness funnels are absent; adding them would alter the accepted marketing contract and its consumer scope. Its compact task-fact pattern is reusable. |
| `mart.crm_interaction` | one interaction, sales/guest scope | `NOT_APPLICABLE`: not one CRM task. |
| `mart.ip_training_daily` | training date × club × service | `NOT_APPLICABLE`: payment/revenue-related training grain is not the client-day DPFU outcome input. |
| `mart.ancillary_revenue_movement` | revenue movement | `NOT_APPLICABLE`: neither task key nor current client/date attribution. |
| `mart.fitness_leads_funnel_task` | designed only | `NEW`: no physical object exists. |

The minimal target remains one separate fact
`mart.fitness_leads_funnel_task` with grain one `Reference106.ID` task in the
four confirmed fitness funnels. A task row may contain pre-aggregated outcome
attributes only after the current client-code/date rules are physically
validated; no booking, DPFU, service or training event row may be joined into
the task grain.

## Fixed boundaries

- BR-003 determines the task horizon; no static one-year replacement is
  approved.
- `has_booking` is the current stage-based task flag, not a booking-row count.
- `training_count`, `has_paid_training_45d` and fallback `service_name` retain
  the current client-code/date attribution, including overlapping 45-day task
  windows and DAX `MIN` name tie behaviour, until a separate approved method
  changes them.
- Power BI keeps distinct task counts, conversion ratios, prior-year and
  cumulative measures. No Power BI/M/DAX artifact changes in this package.
- No watermark is evidenced; an eventual refresh remains an atomic full
  BR-003 rebuild until a separately approved incremental design.

## Runnable-admission blocker

Stage-2 source evidence is now preserved in
`docs/source_metadata/fitness_leads_funnel_stage2_validation_2026-08-24.md`.
It confirms task grain and 45-day controls, but the following physical facts
remain blockers for a one-task fact:

1. two task rows have multiple current services, while 1,432 earliest booking
   dates have multiple DAX-minimised service names;
2. raw technical close dates end the current DAX booking window before its
   task start for 142,255 filtered tasks;
3. raw `Document329.VT4352` is one-to-many for 951 relevant documents.

The screenshots are report observations, not a source-side control value.
Therefore no `CREATE TABLE`, load SQL, reconciliation SQL, rollback script or
source/VM query is reviewed or authorized by this planning package.

## Exact next independent package

`STAGE_2_SERVER_VALIDATION / fitness_leads_funnel`, read-only only: execute
the documented V-01—V-09 and V-11 controls on the four-funnel BR-003 scope;
record key/cardinality/state/client-code/45-day evidence and exact source
control values. It excludes DDL/DML, Power BI/M/DAX, Excel, plans, schedule
and incremental design. Closure is either a confirmed fixed mapping that can
enter runnable admission or a documented unresolved physical blocker.
