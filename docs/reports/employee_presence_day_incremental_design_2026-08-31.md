# Incremental design: `employee_presence_day`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed BR-045 grain is `(presence_date, club_id, employee_id)`. Its
output depends on current client-to-employee links and the approved
`MIN(employee_id)` multi-link rule, so a date-only watermark can miss late
changes. The separate runner takes one source snapshot, stages monthly source
exports, applies only exact full-row differences, then requires the approved
reconciliation and an `EXCEPT ALL` equality check before commit. No watermark
or one-minute SLA is claimed; the full rebuild runner remains unchanged.
