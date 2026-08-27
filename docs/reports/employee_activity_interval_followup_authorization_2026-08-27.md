# Follow-up Stage 2 authorization: coupon payload and nonnegative duty rule

- Date: 2026-08-27
- Package: `employee_activity_interval_followup_stage2_2026-08-27`
- Report: `employee_workload`
- Basis: explicit user instruction of 2026-08-27 to explain the coupon-visit
  ambiguity precisely and to make negative clean-duty values zero.

## Scope

1. Run one exact, read-only refinement of EW-V03B to distinguish differences
   in `quantity × service_time` from visit/contract payload differences after
   current M `Table.Distinct`.
2. Record the user decision: `clean_duty_minutes = greatest(0, raw current-M
   duty minutes minus raw qualifying coupon-overlap minutes)`.
3. Update the report, mapping, contract, ADR, business rule and evidence with
   the observed result and decision.

## Boundary

Only source `REPEATABLE READ, READ ONLY` SQL and local documentation are
allowed. No target connection, DDL, DML, `COPY`, Power BI change or source
mutation is authorized.

## Closure criterion

The minute-impact of coupon duplicates is explicit, the nonnegative-duty rule
is recorded, and the next physical-planning blocker (if any) is named without
creating a mart.
