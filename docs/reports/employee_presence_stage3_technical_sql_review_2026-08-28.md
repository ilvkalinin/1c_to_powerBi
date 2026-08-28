# Technical SQL review: two employee-presence products

Status: `SUPERSEDED BY BR-044/BR-045 / NOT ADMISSIBLE FOR PHYSICAL EXECUTION`.

## Immutable reviewed set

- [mapping](../mappings/employee_workload.md), [contract](../data_contracts/employee_workload.md), [ADR](../adr/0014-employee-workload-multi-fact.md), [BR-043](../catalogs/business_rules.md);
- [personal extract](../../sql/marts/employee_presence_day_extract.sql), [non-personal extract](../../sql/marts/employee_presence_unattributed_day_extract.sql);
- [independent source controls](../../sql/marts/employee_presence_source_controls.sql);
- [DDL](../../sql/marts/employee_presence_ddl.sql) and [target reconciliation](../../sql/tests/employee_presence_reconciliation.sql).

`mart.employee_presence_day` has key `(presence_date, club_id, employee_id)` and originally receives only exact-one employee rows. This reviewed set originally put both BR-043 statuses in `mart.employee_presence_unattributed_day`. BR-044 subsequently excludes the `NO_EMPLOYEE` branch and BR-045 instead puts multi-link visits into the personal product through `MIN(_idrref)`, so neither its extract nor its DDL/reconciliation contract may be physically executed; a new technical review is required.

## Architecture and rollback

VM-1 performs filtering and aggregation in one exported `REPEATABLE READ, READ ONLY` snapshot. A future runner uses `connect_with_retry`, writes only derived target columns to bounded month binary COPY files, closes each source reader, then opens one VM-2 transaction under a transaction-scoped advisory lock. It creates temporary target stages, COPYs both products, compares independent source controls, replaces each isolated table with `DELETE + INSERT`, runs reconciliation before commit and deletes temporary files. Any error rolls back VM-2 and deletes files; no `DROP`, raw replication, source index or long idle target transaction is allowed.

No index is reviewed: the primary keys are sufficient evidence for target uniqueness, while a post-load target read plan must determine any additional index. Refresh is full rebuild only; neither source change timestamp nor deletion watermark is confirmed.

## Representative exact-extract evidence

Fresh source `REPEATABLE READ, READ ONLY`, `[2025-08-01, 2025-09-01)`, no concurrent transport:

| Extract | rows | planning / execution ms | shared hit/read | temp |
|---|---:|---:|---:|---:|
| personal | 16,441 | 7.949 / 465.466 | 305,287 / 1 | 0 |
| non-personal | 367 | 7.309 / 454.497 | 340,178 / 24 | 0 |

This permits a future progressive 1→2→3→6-month ladder, not a full-range claim. Before physical admission the runner must capture independent source rows/minutes/min/max date by product in its own path, run the ladder without parallel COPY, then include target key/NULL/status/horizon controls and an atomic rerun. Power BI remains unchanged by BR-036.

## Physical-admission criterion

An explicit new approval is required for the exact reviewed objects and operations: initial DDL, temporary stage/COPY, `DELETE + INSERT`, reconciliation, rollback, atomic rerun and target read plan. Acceptance requires zero source/stage/target deviations for both products, no duplicate keys/contract violations/future rows, measured target plans and an execution report.
