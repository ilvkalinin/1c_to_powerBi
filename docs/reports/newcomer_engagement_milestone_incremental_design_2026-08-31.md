# Incremental design: `newcomer_engagement_milestone`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed physical key is `(contract_id, client_id, checkpoint_day)`. No
validated source modification watermark covers the member, contract, visit and
freeze inputs used by the current BR-003 extract. The separate incremental
runner therefore takes a repeatable-read, read-only source snapshot, stages it
in the mart, and compares it to the target using `EXCEPT ALL`.

When the sets are equal it commits no final target DML. Otherwise it removes
target rows missing or different from the source stage, inserts missing source
rows, and requires the exact comparison and the existing key/invariant controls
before committing one advisory-lock-protected transaction. The existing full
rebuild loader remains unchanged. This is not a bounded source delta and claims
no incremental SLA. Runtime and scheduling remain blocked pending a separately
approved execution package.
