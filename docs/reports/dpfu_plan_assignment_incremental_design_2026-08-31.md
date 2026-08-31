# Incremental design: `dpfu_plan_assignment`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

`InfoRg6612` has the confirmed six-field logical key
`(plan_date, club_id, activity_id, employee_id, planned_client_key,
plan_line_discriminator)`, but the reviewed source has no confirmed modified
timestamp or history watermark. `plan_date` is a business attribute, not a
safe change boundary. The separate runner therefore reads one bounded BR-003
source snapshot, stages it, compares the complete row multiset with the
existing target, and changes final rows only when the facts differ.

It first deletes changed/absent target rows and then inserts source rows not
already equal to a final row. The source and final table must agree via exact
`EXCEPT ALL` comparison before commit. No watermark and no one-minute SLA are
claimed. The existing full rebuild runner is unchanged; no DML was run during
this design package.
