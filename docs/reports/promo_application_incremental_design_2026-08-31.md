# Incremental design: `promo_application`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed target key is `report_row_id`. The existing delivery runner has
an independent current-PBIT control path, but no validated modification
watermark for the source branches. The separate incremental runner preserves
the source-first snapshot and PA-R01—R10 reconciliation.

It stages the full BR-003 source output and uses full-row `EXCEPT ALL` to
compare it with the target. Equal sets cause no final DML; otherwise it deletes
only absent or changed target rows and inserts only missing stage rows, then
requires an exact final comparison and current-PBIT reconciliation before
commit. The full rebuild loader is unchanged. This is full-horizon target
synchronisation, not a bounded source delta, and claims no SLA. Runtime and
scheduling remain blocked pending a separately approved package.
