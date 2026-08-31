# Incremental design: `administrator_bookings_daily`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed key is `(booking_source, booking_id)`. The separate runner
preserves monthly source transport and AB-R01—R06 reconciliation, but stages
all source rows and exact-diffs the target rather than truncating it. No
watermark/SLA is claimed; runtime and scheduling remain blocked.
