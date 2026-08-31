# Incremental design: `newcomer_engagement_second_month`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed physical key is `source_row_id`; duplicate
`(contract_id, client_id, month_of_engagement)` pairs are intentionally
preserved. The runner keeps the existing monthly source transport within one
repeatable-read source snapshot and retains its source-to-stage controls.

It is separate from the full rebuild loader. It stages the full BR-003 source
snapshot, compares full rows to the target with `EXCEPT ALL`, and performs no
final DML when equal. For differences it deletes only target rows absent or
changed in the stage and inserts only missing stage rows. Exact equality and
all existing persisted controls are required before the one advisory-lock
transaction commits. This is target-side incrementality only: no source
watermark or incremental SLA is claimed; execution and scheduling remain
blocked pending their separately approved package.
