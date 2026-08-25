# Stage 2 readiness: package-aware snapshot и retention «Клиентской базы»

- Package: `client_base_snapshot_retention_packages_readiness_2026-08-25`
- Stage: `STAGE_2_SERVER_VALIDATION`
- Status: `VALIDATION_IN_PROGRESS`
- Source mode: one `REPEATABLE READ READ ONLY` snapshot per control; no DDL,
  DML, COPY, target object or Power BI change.

## Подтверждённые общие источники

| Проверка | Наблюдение | Статус |
|---|---:|---|
| physical types | клиентские/клубные/contract references — `bytea`; даты — `timestamp without time zone`; visit quantity — `numeric(15,2)` | CONFIRMED |
| `Reference141X1` gender | только два non-NULL reference code в sample cohort: 45 906 / 33 719 clients | CONFIRMED |
| birth date | 1 / 79 625 membership clients has NULL/sentinel birth date | CONFIRMED; maps to `Не указано` |
| tenure values | `New` 356 278, `Ex` 480 251, `Renew` 252 953 history rows | CONFIRMED |
| tenure as-of at 2026-07-01 | 80 736 / 81 054 active membership clients have a prior record; 318 map to `Не указано`; latest-period ties 0 | CONFIRMED |
| visit source | 371 620 qualified 30-day movements; direct registry client equals `Document325` client in all 371 620 rows; all are `Active=true`, `Posted=true`, `Marked=false` | CONFIRMED for the sample; no new status filter introduced |
| package check state | 14 621 qualified child rows are `Posted=true`, `Marked=false` at the sample boundary | CONFIRMED current branch evidence |
| membership state after current filters | 80 988 rows, all `Marked=false` | CONFIRMED sample |
| club mapping | 22 physical IDs, 22 names, duplicate name groups 0 | CONFIRMED |
| child sentinel control | 0 sentinel / 0 NULL of 20 823 BR-003 candidate rows | CONFIRMED; current BR-018 predicate and measured plan are equivalent on this horizon |

The source universe in `sql/marts/client_base_snapshot_extract.sql` preserves
the already validated BR-037 sales/return/max-start rule and BR-038 priority:
child package precedes normal membership before club and network dedupe. It
also deliberately preserves the current child sentinel predicate under BR-018;
this package does not silently normalise it.

## Snapshot source controls and performance

The July sample contained the report dates 2026-07-01, 06, 13, 20 and 27.
For every date and both scopes the source extract total equals the independent
daily interval control: 10/10 controls, tolerance 0, differences 0.

| Date | club | network |
|---|---:|---:|
| 2026-07-01 | 93 921 | 93 838 |
| 2026-07-06 | 93 950 | 93 867 |
| 2026-07-13 | 94 082 | 93 999 |
| 2026-07-20 | 94 347 | 94 259 |
| 2026-07-27 | 94 386 | 94 290 |

Performance was measured in the required order: exact representative sample,
then full horizon. The initial client-date lateral design ran 41.394 s with
21.725m shared-hit blocks. Replacing repeated tenure as-of and client-card
lookups with source-side effective intervals and one static client lookup
reduced the sample to 16.147 s and 2.632m shared-hit blocks. The optimized
full BR-003 `[2025-01-01, 2027-01-01)` `EXPLAIN (ANALYZE, BUFFERS)` produced
1 743 244 target-grain aggregate rows in 490.560 s, 11 416 353 shared blocks
and 6 909 365 temporary-read blocks.

`CONFIRMED`: this is a rare full-rebuild baseline only. It is not an
incremental refresh or a claim of the daily one-minute SLA. Any future runner
must use bounded source batches, one target transaction, binary COPY, same-run
source/stage/target controls and atomic rollback; it must not start until an
immutable reviewed DDL/DML plan is approved.

## Retention source control

The independent control in
`sql/marts/client_base_retention_source_control.sql` forms the two baseline
sets and the current network set from the same BR-037/BR-038 source universe,
then performs the retention semi-join without exposing client IDs. Its
2026-07-01 results have no `retained > baseline` breach.

| comparison type | scope | baseline | retained | retained current child-package clients |
|---|---|---:|---:|---:|
| `previous_year` | club | 87 822 | 51 467 | 4 588 |
| `previous_year` | network | 87 719 | 51 392 | 4 580 |
| `year_start` | club | 87 401 | 68 273 | 8 617 |
| `year_start` | network | 87 281 | 68 165 | 8 591 |

The exact point control plan took 5.803 s, used 1 345 627 shared-hit blocks,
and had no temporary spill. Report-date comparison formation remains a small
deterministic calendar operation: first-of-month maps to the same first of the
previous year; Monday maps to the nearest Monday to the previous-year calendar
date. The control uses both `year_start` and `previous_year` branches.

`CONFIRMED`: retention has package-aware source baseline/current formation and
semi-join evidence. `NOT_EXECUTED`: its physical fact, target DDL/DML, COPY,
target reconciliation and rerun.

## Stage 3 boundary

The exact future DDL/load/reconciliation runner cannot be approved in this
read-only package: the snapshot full-rebuild evidence requires bounded batches
and an atomic target transaction, while the target relations do not exist.
The next package must contain immutable source extracts (including retention
attribute grouping), reviewed DDL/rollback, batch runner and same-run
source/stage/target controls before it can perform any DDL/DML. This is a
stage/authority boundary, not a source-data blocker.

## Explicit boundary

No PostgreSQL mart was created or changed, no data was copied, and Power BI was
not changed. Stage 3 remains blocked until an immutable reviewed SQL plan is
explicitly approved.
