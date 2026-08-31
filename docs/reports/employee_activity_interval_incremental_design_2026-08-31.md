# Incremental design: `employee_activity_interval`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The fact has a confirmed stable `activity_event_key`, but its PZ/GZ, duty and
coupon branches include current-state registers, cancellations and approved
tie-breaks. No confirmed modified timestamp covers the composed output, so an
arbitrary lookback would miss late corrections. The separate runner therefore
exports the existing reviewed four-branch projection from one source snapshot,
stages it, and changes final rows only when their complete values differ.

The stage retains the existing source-control totals and key/contract checks;
post-delta it runs the existing target reconciliation plus an exact `EXCEPT
ALL` source-stage/target comparison before commit. No watermark or one-minute
SLA is claimed. The existing full rebuild and its files were not changed.
