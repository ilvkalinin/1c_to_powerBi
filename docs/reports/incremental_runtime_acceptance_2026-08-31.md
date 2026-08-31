# Runtime acceptance: all incremental runners

Status: `NOT_EXECUTED`.

This checklist is deliberately not evidence of a successful refresh. It is the
required VM2 runtime sequence for each job in
`config/project_refresh_orchestration.json`:

1. run the runner's non-DML validation mode where supported, then collect the
   representative source `EXPLAIN (ANALYZE, BUFFERS)` required by the project
   policy;
2. run exactly one `--run` invocation without concurrent heavy source work;
3. record elapsed time, source/stage/persisted controls and exact target diff;
4. compare the resulting target with its approved full-rebuild result for the
   same source snapshot; and
5. only after all four pass, decide its schedule, concurrency and timeout.

Acceptance units, in deterministic manifest order:

- `administrator_bookings_daily`
- `administrator_card_gymmy_daily`
- `children_package_sale`
- `client_base_daily`
- `client_base_snapshot_retention`
- `club_attendance_hourly`
- `contract_usage`
- `crm_br032`
- `dpfu_plan_assignment`
- `employee_activity_interval`
- `employee_presence_day`
- `fitness_funnel_client_outcome`
- `fitness_funnel_client_start`
- `fitness_leads_funnel`
- `ip_training_daily`
- `lesson_room_slot_5m`
- `marketing_funnel`
- `membership_receipts`
- `newcomer_engagement_milestone`
- `newcomer_engagement_second_month`
- `newcomer_guest_visits`
- `prebooking_state_event`
- `preparation_renewal_checkpoint`
- `promo_application`
- `renewal_management_observation_chain`
- `revenue_refresh_chain`
- `unconfirmed_service_debt_movement`
- `visit_client_day`
- `group_lesson`

No unit has runtime acceptance yet. The existing full-horizon target-diff
runners must not be represented as a one-minute SLA until this evidence exists.

## Local read-only plan attempts

- `unconfirmed_service_debt_movement`: source plan ladder measured separately
  in `unconfirmed_service_debt_movement_incremental_performance_2026-08-31.md`.
- `client_base_daily`: the current runner's full-horizon source fingerprint
  `EXPLAIN (ANALYZE, BUFFERS)` did not return within the local 30-second
  observation window. The source session was no longer active afterwards.
  A safe progressive ladder was then measured with the exact fingerprint:

  | Window | Rows | Execution time | Shared hit/read | Temp read/write |
  |---|---:|---:|---:|---:|
  | 2026-08-01 .. 2026-09-01 | 31 | 7,483.035 ms | 1,395,311 / 0 | 1,285 / 2,887 |
  | 2026-07-01 .. 2026-09-01 | 62 | 8,585.290 ms | 1,437,436 / 0 | 1,885 / 7,569 |
  | 2026-06-01 .. 2026-09-01 | 92 | 9,761.552 ms | 1,477,770 / 1 | 2,981 / 8,664 |

  The measured temporary spill means that a full-horizon plan remains
  `NOT_MEASURED`; it is not a performance conclusion or SLA result.

- `administrator_bookings_daily`: exact source extract, one-month window
  `2026-08-01 .. 2026-09-01`, measured 620 rows in 4,839.994 ms with
  3,927,335 shared hits, 4,800 shared reads and no temporary I/O. This is
  source-only evidence; transport, target diff and reconciliation remain
  `NOT_EXECUTED`.

- `administrator_card_gymmy_daily`: exact source extract, one-month window
  `2026-08-01 .. 2026-09-01`, measured 348 rows in 1,877.649 ms with 76,270
  shared hits, 4,714 shared reads and no temporary I/O. This is source-only
  evidence; transport, target diff and reconciliation remain `NOT_EXECUTED`.

- `children_package_sale`: exact source extract, one-month window
  `2026-08-01 .. 2026-09-01`, measured 1,821 rows in 232.356 ms with 100,255
  shared hits, 59 shared reads and no temporary I/O. This is source-only
  evidence; transport, target diff and reconciliation remain `NOT_EXECUTED`.
