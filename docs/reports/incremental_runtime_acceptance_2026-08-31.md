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

- `visit_client_day`: exact source extract, one-month window
  `2026-08-01 .. 2026-09-01`, measured 301,084 rows in 3,727.149 ms with
  2,724,236 shared hits, 7,951 shared reads and no temporary I/O. This is
  source-only evidence; transport, target diff and reconciliation remain
  `NOT_EXECUTED`.

- `group_lesson`: exact base source extract, one-month window
  `2026-08-01 .. 2026-09-01`, measured 14,990 rows in 84.208 ms with 19,866
  shared hits, 964 shared reads and no temporary I/O. The dependent target-side
  lookup of `mart.prebooking_state_event`, transport, diff and reconciliation
  remain `NOT_EXECUTED`.

- `prebooking_state_event`: exact source extract, one-month window
  `2026-08-01 .. 2026-09-01`, measured 97,711 rows in 1,930.961 ms with
  1,424,912 shared hits, 3,842 shared reads and no temporary I/O. This is
  source-only evidence; transport, target diff and reconciliation remain
  `NOT_EXECUTED`.

- `membership_receipts`: primary exact source extract, one-month window
  `2026-08-01 .. 2026-09-01`, measured 16,314 rows in 1,984.152 ms with
  517,902 shared hits, 9,126 shared reads and no temporary I/O. Contract
  history, price/freeze auxiliary queries, transport, target diff and
  reconciliation remain `NOT_EXECUTED`.

- `newcomer_engagement_milestone`: `BLOCKER` for a **true incremental
  refresh**. The currently committed `_incremental.py` is a separate runner,
  but its `target_row_diff` algorithm still reads the complete BR-003 source
  snapshot (`2025-01-01 .. current date`) and must not be called an
  incremental design. It remains schedule-blocked.

  Read-only source-plan evidence was captured in separate `REPEATABLE READ,
  READ ONLY` sessions. The same exact weekly extract
  `2026-08-24 .. 2026-09-01` first returned 5,538 rows in 18,609.011 ms with
  40,343/68,876 temporary read/write blocks. Changing only the query-local
  setting to `SET LOCAL work_mem = '512MB'` preserved the 5,538 output rows,
  reduced elapsed time to 16,936.208 ms and eliminated temporary I/O. The
  progressive source ladder with that same session-local setting was:

  | Window | Rows | Execution time | Shared hit/read | Temp read/write |
  |---|---:|---:|---:|---:|
  | 2026-08-01 .. 2026-09-01 | 18,673 | 17,398.474 ms | 2,189,216 / 0 | 0 / 0 |
  | 2026-07-01 .. 2026-09-01 | 33,305 | 19,946.811 ms | 2,311,789 / 2,242 | 0 / 0 |
  | 2026-06-01 .. 2026-09-01 | 46,766 | 16,856.798 ms | 2,433,739 / 0 | 0 / 0 |
  | 2026-03-01 .. 2026-09-01 | 105,957 | 26,426.329 ms | 2,936,463 / 9,242 | 0 / 0 |

  The complete current BR-003 source snapshot did not return a plan result in
  the available 30-second observation window even with `work_mem = '512MB'`.
  No target DML, transport, target diff, target reconciliation or Power BI
  refresh was run.

  A source-watermark inventory was then performed before narrowing the
  extract. The fact depends on `Reference59`, `Reference141X1`, `Document346`
  and two document tabular sections, three accumulation registers, an
  information register, and employee sources. The three reference/document
  tables expose `_version`, but it is not a global monotonic change cursor:
  `Reference59` has 2,088,773 rows but only 155 distinct values (`0..449`),
  `Reference141X1` has 876,888 rows but 58 (`0..81`), and `Document346` has
  3,131,217 rows but 23 (`0..53`). The three movement registers used by the
  extract do not expose `_version`. The read-only catalogue search found no
  change-log/audit relation by name and no non-internal trigger on the eleven
  participating source relations. The source PostgreSQL instance reports
  `wal_level = replica` and has neither publications nor replication slots;
  therefore logical-replication CDC is not available from this connection
  without source-infrastructure changes. `_marked` alone cannot reveal changed
  or deleted movement rows.

  Therefore a bounded output-date window would miss unbounded late
  corrections and deletions under the confirmed current rule. Required input
  for a real incremental design is one of: an authoritative source change
  feed/watermark covering every dependency and deletions; or an explicitly
  approved finite late-correction retention rule. Until then the only
  correctness-preserving mode is the documented bounded full rebuild, not a
  scheduled incremental refresh. The local `work_mem` observation is not a
  server-default recommendation and does not establish an SLA.

  `DECISION_REQUIRED — rolling two-month alternative`: a separate
  `bounded_sliding_window` runner can source-rebuild only checkpoint dates in
  `[first day of current month - 1 month, tomorrow)`, atomically delete and
  reinsert only that target window, preserve older BR-003 rows, and derive
  source membership starts up to 30 days before the window when needed for the
  five checkpoints. The measured two-month exact extract is the
  `2026-07-01 .. 2026-09-01` ladder step above (33,305 rows, 19,946.811 ms,
  no temp I/O). This alternative is **not** a permanent incremental: it is
  correct only if an approved business rule bounds corrections and deletions
  to two months, or if a separate rare full rebuild remains the documented
  history-reconciliation operation. A separate runner/configuration now
  implements this candidate; it keeps
  `late_change_evidence = ASSUMPTION`, `watermark = null`, `incremental_sla =
  null`, and the manifest's `scheduling_status = BLOCKED`. Its target-side
  runtime, reconciliation and Power BI time are still `NOT_EXECUTED`. A
  read-only target plan was additionally captured for the same two-month
  window: `SELECT count(*)` took 704.528 ms and read 20,131 shared blocks.
  The target has only its primary-key index `(contract_id, client_id,
  checkpoint_day)`, not a `checkpoint_date` index. The non-executing
  `EXPLAIN (FORMAT JSON)` of the runner's exact window `DELETE` is a
  `ModifyTable → Seq Scan`, estimating 31,293 affected rows. It is planning
  evidence only: the `DELETE`, `INSERT`, atomic commit and target
  reconciliation have not been executed.

- `newcomer_engagement_second_month`: `BLOCKER` for the same rolling-window
  strategy. Its current separate runner is still `target_row_diff` over the
  full BR-003 horizon. The exact two-month source extract
  `2026-07-01 .. 2026-09-01` did not return an `EXPLAIN (ANALYZE, BUFFERS)`
  result in the available 30-second observation window, even with
  `SET LOCAL work_mem = '512MB'`; no DML was run. SQL review identifies the
  cause before the output month boundary: `child_raw` always reads check rows
  from `2023-01-01`, then `child_sales`, the latest-start/rank sequence,
  all tenure history and the SPT branch are computed before the `$1/$2`
  `month_of_engagement` filter. Moving that boundary earlier can change the
  confirmed current child-package semantics, so it must not be done as a
  performance-only edit. This mart remains on the current item until an
  evidence-preserving source reduction or an approved business rule exists.

  A non-executing plan isolates a possible evidence-preserving optimisation
  candidate, but does not validate it: the root cost is `734,931.53` for an
  estimated 25 output rows; `child_sales` costs `263,162.96`, all
  `tenure_history` costs `116,823.63` for an estimated 1,088,113 rows, and
  `spt_pairs` costs `195,588.43`. The final child output is already filtered
  before tenure is joined. An incremental-specific extract may therefore
  restrict tenure history to those surviving child client keys, but it needs
  exact result-set equality evidence against the current extract before it
  can replace the source query.

  The candidate was rejected. It returned 11,025 rows in 15,192.413 ms, but
  exact `EXCEPT ALL` comparison with the current extract found 10 different
  rows. After the same source pages were warm, the unchanged exact extract
  returned the same 11,025 rows in 10,145.841 ms without temporary I/O.
  Therefore no source-SQL optimisation is adopted: a rolling two-month runner
  must use the unchanged extract and still needs a cold-run measurement before
  scheduling.
