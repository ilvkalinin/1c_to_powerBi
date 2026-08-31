# Incremental design: `marketing_funnel`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The task and task×contract facts have confirmed keys, but CRM and contract
current-state dependencies have no validated output watermark. This separate
runner stages one source snapshot, removes bridge before task, inserts task
before bridge, and requires exact `EXCEPT ALL` plus MF-R01—R06 before commit.
The full rebuild remains unchanged and no SLA is claimed.
