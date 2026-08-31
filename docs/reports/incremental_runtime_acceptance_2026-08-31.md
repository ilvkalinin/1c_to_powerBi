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
  observation window. The source session was no longer active afterwards. This
  is `NOT_MEASURED`, not a performance conclusion; use a bounded progressive
  horizon on VM2 before attempting the full range.
