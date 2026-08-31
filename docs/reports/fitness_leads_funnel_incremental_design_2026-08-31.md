# Incremental design: `fitness_leads_funnel`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The reviewed task and bridge outputs depend on CRM/DPFU current states and a
45-day qualification, so no validated watermark exists. The separate runner
stages one source snapshot, deletes bridge before task, inserts task before
bridge, and requires exact `EXCEPT ALL` equality plus existing reconciliation.
The full rebuild remains unchanged; no SLA is claimed.
