# Incremental design: `preparation_renewal_checkpoint`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed physical key is `(contract_id, checkpoint_day)`. The extract
depends on the approved current-M preparation/renewal logic and has no validated
change watermark. The separate runner keeps the existing quarterly transport
and independent source controls inside one repeatable-read, read-only snapshot.

All batches enter a target stage. Exact full-row `EXCEPT ALL` comparisons cause
no final DML when equal; otherwise only target rows absent or changed in the
stage are deleted and only missing stage rows are inserted. Existing PR-R01—R06
reconciliation and an exact final comparison are required before the locked
transaction commits. The full rebuild loader remains unchanged. This does not
claim a bounded-source incremental SLA; runtime and scheduling remain blocked.
