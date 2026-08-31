# Incremental design: `children_package_sale`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The target key is `report_row_id`. The separate runner preserves the approved
exported repeatable-read snapshot and monthly readers, stages the complete
source output, checks the existing controls, then exact-diffs full rows. No
watermark/SLA is claimed; runtime and scheduling remain blocked.
