# Incremental design: `ip_revenue_daily`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The new runner preserves the confirmed source snapshot, stage integrity and
target controls, but synchronises full rows with `EXCEPT ALL` rather than
clearing the target. No source watermark or SLA is claimed; runtime and
scheduling remain blocked.
