# Incremental design: `prebooking_state_event`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed physical key is `(booking_kind, recorder_tref, recorder_id,
source_line_no, legacy_settlement_line_no)` with `NULLS NOT DISTINCT`; it
retains the approved legacy PZ multiplicity. No validated source update
watermark covers the multi-branch extract.

The new runner is separate from the full rebuild loader. It stages a single
repeatable-read, read-only BR-003 source snapshot, requires source and stage
controls to agree, and uses full-row `EXCEPT ALL` to detect drift. Equal sets
produce no final target DML. Otherwise it removes only absent or changed target
rows and inserts only missing staged rows; exact equality and persisted controls
are required before one advisory-lock transaction commits. It is not a bounded
source delta and claims no incremental SLA. Runtime and scheduling stay blocked.
