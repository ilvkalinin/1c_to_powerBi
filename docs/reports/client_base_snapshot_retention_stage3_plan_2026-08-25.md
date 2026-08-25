# Stage 3 planning: `client_base_snapshot` и `client_base_retention`

Статус: `REVIEWED PLANNING / DDL-DML NOT APPROVED`.

## Immutable set for execution approval

- `sql/marts/client_base_snapshot_extract.sql`
- `sql/marts/client_base_retention_extract.sql`
- `sql/marts/client_base_snapshot_ddl.sql`
- `sql/marts/client_base_retention_ddl.sql`
- `sql/marts/client_base_snapshot_target_replace.sql`
- `sql/marts/client_base_retention_target_replace.sql`
- `sql/marts/client_base_retention_source_control.sql`

Both facts are physical aggregate tables with `UNIQUE NULLS NOT DISTINCT` on
their contract grain. The runner must follow the reviewed daily transport
pattern: one `REPEATABLE READ READ ONLY` source snapshot, monthly bounded
binary COPY files, one target transaction with advisory locks, temporary stage
tables, independently captured controls, then DDL + replacement DML only
before commit. Any failure rolls back target and source; automatic DROP is
forbidden. Power BI remains unchanged.

## Measured evidence

- Snapshot July sample: 10/10 independent daily scope controls, zero deviation.
- Snapshot full BR-003 baseline: 1,743,244 aggregate rows, 490.560 s; rare
  full rebuild only, not incremental SLA.
- Retention `year_start`/`previous_year × club/network` source control: four
  rows, zero `retained > baseline` violations.
- Retention generic July sample: 18.611 s after removing repeated client-date
  as-of lookup; 4,229,348 shared-hit blocks.

## Required execution acceptance

Before commit: target logical-key/contract/horizon checks and exact equality of
source/stage controls. After commit: target reconciliation, target read plans,
sizes and a complete atomic rerun with a fresh source snapshot. Full rebuild
must never be described as the daily incremental refresh.

## Approval boundary

The exact DDL/DML and transport plan above has been prepared but not executed.
Target object creation, COPY and replacement DML require one explicit Stage 3
product-admission approval for this immutable set.
