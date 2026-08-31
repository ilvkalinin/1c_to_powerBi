# Incremental design: `dpfu_ancillary_revenue`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

`mart.ancillary_revenue_movement` is shared with the reception scope. The
separate DPFU runner stages the confirmed 7575/7646 source snapshot with
`revenue_scope='dpfu'`, retains existing source/stage controls and technical-key
collision checks, and compares only the DPFU target slice by complete rows.

When equal it changes no final target rows. Otherwise it deletes only DPFU rows
absent or different from stage and inserts only missing DPFU rows. Reception
controls are captured before and must be unchanged before commit. This is a
full-horizon target synchronisation, not a bounded-source delta; no SLA is
claimed and runtime/scheduling remain blocked.
