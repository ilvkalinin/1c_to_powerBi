# Incremental design: `renewal_management_observation_chain`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

`mart.renewal_management_contract` is current state with confirmed key
`expiring_contract_id`; it can be synchronised from the current-M source
snapshot by full-row exact diff. `mart.renewal_management_contract_observation`
is append-only history keyed by `(expiring_contract_id, observed_at)` and must
not be target-diffed or deleted.

The new parent runner stages the confirmed source snapshot, checks RM-R01—R05,
then deletes only stale current-state rows and inserts only missing rows. The
new chain runner invokes it first, and only after a successful parent commit
calls the existing append-only observation runner. The latter remains the
authoritative history algorithm and RMO reconciliation remains unchanged. No
watermark or SLA is claimed; execution and scheduling remain blocked.
