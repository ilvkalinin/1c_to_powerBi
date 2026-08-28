# Revised technical SQL review: `mart.employee_presence_day`

Status: `REVIEWED / READY FOR SEPARATE PHYSICAL ADMISSION`.

## Immutable reviewed set

- [mapping](../mappings/employee_workload.md), [contract](../data_contracts/employee_workload.md),
  [ADR](../adr/0014-employee-workload-multi-fact.md), [BR-044/BR-045](../catalogs/business_rules.md);
- [BR-045 extract](../../sql/marts/employee_presence_day_br045_extract.sql);
- [independent source controls](../../sql/marts/employee_presence_day_br045_source_controls.sql);
- [DDL](../../sql/marts/employee_presence_day_br045_ddl.sql) and
  [target reconciliation](../../sql/tests/employee_presence_day_br045_reconciliation.sql).

The only planned target is `mart.employee_presence_day` with key
`(presence_date, club_id, employee_id)`. A qualified visit enters when its
client has at least one `Reference225` row; its target employee is the stable
technical `MIN(_idrref)` for that client. No-link visits are excluded. This is
the explicit BR-044/BR-045 target method, not reproduction of current-M
employee attribution. The earlier two-product reviewed set is superseded.

## Architecture and rollback

At a future physical admission, VM-1 will read one bounded period in a fresh
`REPEATABLE READ, READ ONLY` snapshot through `connect_with_retry` and write
only the four target columns to a temporary derived binary COPY file. The
reader closes before VM-2 opens one short transaction under an advisory lock;
the runner loads a temporary stage, checks independent source values, replaces
the isolated table with `DELETE + INSERT`, runs target reconciliation and then
commits. Any failure rolls back VM-2 and removes the temporary file. No raw
replica, source mutation, target connection, index or Power BI change is part
of this package.

## Validation status

`VALIDATION_PENDING`: no exact BR-045 source control or `EXPLAIN ANALYZE` was
executed, because the approved revised-planning scope excludes source/target
execution. The previous two-product source plans do not validate this extract.
Before physical admission, capture independent source rows/minutes/min/max,
retained visit IDs, excluded no-link IDs and multi-link IDs, then run a
one-month exact-extract `EXPLAIN (ANALYZE,
BUFFERS)` without parallel transport. Continue a 1→2→3→6-month ladder only
after each prior step records rows, time, I/O, temp spill and connection result.

## Physical-admission criterion

A new explicit approval must name the one table and operations: DDL, bounded
source binary COPY, stage load, `DELETE + INSERT`, independent controls,
in-transaction reconciliation, atomic rerun and target read plan. Acceptance
requires zero deviations for source/stage/target rows and minutes, key/NULL/
horizon contract checks, measured target plans and an execution report. Power
BI remains unchanged.
