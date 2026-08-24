# Stage-3 planning: «Воронка лиды фитнес»

Статус: `BLOCKED — exact runnable admission requires a new read-only source-validation package`.

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

The existing evidence is insufficient to author exact source SQL, target DDL
or reconciliation without inventing physical rules. The missing confirmed
inputs are:

1. full four-funnel task key/cardinality and BR-003 counts, beyond SV-078's
   bounded 100-task sample;
2. source-state filters (`Marked`, `Active`, `Posted`, cancellations) for
   task, booking and DPFU branches;
3. uniqueness, null behaviour and cross-set stability of client code used by
   the current outcome attribution;
4. full task-to-service cardinality and the exact current `MIN` fallback
   behaviour when several services occur on the earliest booking date;
5. physical reproduction of the inclusive 45-day outcome interval and
   independent source controls for the displayed task, booking and training
   measures.

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
