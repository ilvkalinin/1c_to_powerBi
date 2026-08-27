# Stage 2 authorization: `employee_activity_interval` source validation

- Date: 2026-08-27
- Package: `employee_activity_interval_stage2_validation_2026-08-27`
- Report: `employee_workload`
- Stage: `STAGE_2_SERVER_VALIDATION`
- Basis: explicit user approval after the documented global gate audit
  `docs/reports/global_gate_employee_activity_interval_readonly_2026-08-27.md`.

## Scope

Run EW-V01--EW-V07 in short fresh `REPEATABLE READ, READ ONLY` source
sessions using the shared retry policy. The controls cover physical fields and
states of activity sources, event-key/cardinality of `InfoRg7006` and
`Document329.VT4352`, coupon--duty overlap, SCUD-to-employee cardinality,
historical employment attribution, and independent count/minute/reuse totals.
Record expected result before each statement and preserve SQL, snapshot,
actual result, duration and any reproducible exception.

## Boundaries

No target DDL/DML/COPY, no new mart, no Power BI/M/DAX change, no source write,
no external-file analysis and no methodology change. A discrepancy is evidence,
not permission to deduplicate, select a tie or normalize an overlap.

## Closure criterion

Every EW-V01--EW-V07 is `PASS`, `BLOCKED` or `DECISION_REQUIRED` with exact
evidence; mapping/contract/ADR record confirmed outcomes; and a future Stage 3
plan names any remaining user decision instead of hiding it in SQL.
