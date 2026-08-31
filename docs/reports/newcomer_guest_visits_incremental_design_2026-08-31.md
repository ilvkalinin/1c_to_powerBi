# Incremental design: `newcomer_guest_visits`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The facts `mart.new_first_visit` and `mart.guest_visit_conversion` have
confirmed keys `contract_id` and `(client_id, guest_visit_date)` respectively.
No change watermark is validated for their source logic. The separate runner
therefore transports both extracts from one repeatable-read, read-only source
snapshot, and uses exact full-row `EXCEPT ALL` comparisons before final DML.

If neither fact changed it commits no final DML. Otherwise each target loses
only rows absent or different from its stage and receives only missing stage
rows; the existing NV-R01—R06 reconciliation runs before commit. The full
rebuild loader remains unchanged. This is a full-horizon target synchronisation,
not a bounded source delta, so it claims no incremental SLA. Execution and
scheduling remain blocked pending separately approved runtime work.
