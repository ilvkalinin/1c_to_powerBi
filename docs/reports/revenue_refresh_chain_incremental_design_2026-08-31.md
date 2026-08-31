# Incremental design: `revenue_refresh_chain`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The chain runs separate exact-diff refreshes in confirmed dependency order:
DPFU scope, reception scope, IP daily revenue, then group summary. The summary
is built after its reused target inputs are current. Each runner retains its
existing controls; no source watermark or SLA is claimed. Runtime and scheduler
activation remain blocked.
