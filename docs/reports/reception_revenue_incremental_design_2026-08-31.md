# Incremental design: `reception_revenue`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The reception segment shares `mart.ancillary_revenue_movement` with DPFU. The
separate runner stages its eight controlled categories from a read-only source
snapshot and exact-diffs only `revenue_scope='reception'`. It preserves DPFU
controls before/after, blocks technical-key collisions, and claims neither a
watermark nor SLA. Runtime and scheduling remain blocked.
