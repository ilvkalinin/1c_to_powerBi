# Stage 2 validation: `mart.employee_presence_day`

- Package: `employee_presence_day_stage2_validation_2026-08-28`
- Report: `employee_workload`
- Source: 1C PostgreSQL VM-1
- Horizon: BR-003 `[2025-01-01, 2026-08-28)`
- Execution: 2026-08-28; a fresh `REPEATABLE READ, READ ONLY` connection for
  each control through `connect_with_retry`.
- Target connection, DDL, DML, `COPY`, source mutation and Power BI change:
  none.

## Current-M rule confirmed

The local query `Посещения сотрудников 2025-1 (4)` selects the current path
`AccumRg7575 → Document325 → Reference225`, only visits with the confirmed
operation ID, contracts whose service parent is `Служебная`, and clubs other
than the two current exclusions. It attributes the `AccumRg7575` client to an
employee, clips an open or after-day-end `Document325` end timestamp to the
end of the start day, then sums hours by `club × period × employee name`. It
has no `Marked` or `Posted` predicate. The control SQL uses stable IDs and
numeric minutes, but preserves that source rule.

## Control results

| Check | Expected before execution | Actual | Status |
|---|---|---|---|
| EPD-V01 | All 22 mapped fields exist once. | 22/22 fields present; all ID links are `bytea`, timestamps and state flags match the physical catalog. | PASS (0.4 s) |
| EPD-V02 | Current-M source path is reproducible without silently adding state filters. | 441,224 output rows; 440,516 distinct visit IDs; 142,159,039.48226018333334070180 minutes; dates 2025-01-01…2026-08-27; 0 null starts, 2 open ends, 64,387 after-day ends, 0 negative intervals, 0 marked and 0 unposted rows. | PASS (5.204 s); open/late ends are clipped exactly as M. |
| EPD-V03 | Report every multiplication path; do not deduplicate it. | 708 visit IDs have two current-M rows and two current-M employees; maximum is 2. No other current-M multiplication was observed. | PASS as evidence (4.708 s); the 708 rows cannot be collapsed without a rule. |
| EPD-V04 | Zero qualified visits with several employee links. | Of 469,947 qualified visit IDs, 439,808 have one employee, 29,431 have none, and 708 have two; maximum employees per client is 2. | BLOCKED (10.316 s). |
| EPD-V05 | A candidate contains only one-employee events and no negative minutes. | The restricted domain has 439,808 source/visit rows, 350,346 `employee × date × club` groups and 141,383,578.78226548333333983510 minutes; 0 negative groups; dates 2025-01-01…2026-08-27. | PASS for the restricted control only (6.835 s). |

## Outcome

`mart.employee_presence_day` is `BLOCKED`.  The restricted one-employee
domain omits 30,139 current-M-qualified visits: 29,431 lack an employee and
708 have two employees. Retaining all current-M rows violates the required
one-person grain and duplicates the 708 visits; dropping or allocating any of
those rows changes the current result and requires an explicit methodology
decision. No employee was selected from a multi-link and no target fact was
created.

The initial EPD-V02 statement used `marked` rather than physical `_marked`,
failed before producing a result, and was rolled back. The corrected statement
was then rerun in a new fresh read-only session; only the successful rerun is
the accepted evidence.

## Sources

- [authorization](employee_presence_day_stage2_authorization_2026-08-28.md);
- [expected controls](employee_presence_day_stage2_expected_controls_2026-08-28.md);
- [read-only SQL](../../sql/marts/employee_presence_day_source_controls.sql);
- [current Power Query](../source_reports/employee_workload/Загрузка%20сотрудникво.txt).
