# Incremental design: `membership_receipts`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The shared receipt movement fact has a confirmed composite unique key and the
contract KPI fact has primary key `kpi_unit_key`. The source extract also uses
contract history, price movements, and freezes; no validated change watermark
covers those dependencies.

`scripts/load_membership_receipts_incremental.py` is separate from the full
rebuild loader. It opens one repeatable-read, read-only source snapshot,
derives both final stages using the existing confirmed transformations, and
compares each complete stage to its target with `EXCEPT ALL`. It performs no
final target DML when both are equal. Otherwise, it deletes target rows absent
or different from their stage and inserts missing stage rows in one target
transaction guarded by a mart-specific advisory lock. The final exact checks
and the existing source/persisted controls are required before commit.

This is an incremental target synchronisation, not a bounded source delta:
the source snapshot is full for the BR-003 horizon. No incremental SLA is
claimed. Runtime execution and scheduling remain blocked pending their
separate approved package; `--plan-only` performs no connection or DML.
