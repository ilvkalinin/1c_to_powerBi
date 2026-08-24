# Reviewed Stage-3 admission plan: «Маркетинговая воронка»

Статус: `IMPLEMENTED / INITIAL LOAD AND RERUN PASSED 2026-08-24`.

## Objects and operations

The future runnable package is limited to two new objects:

| Object | Grain | Operation |
|---|---|---|
| `mart.marketing_funnel_task` | one CRM task | `CREATE TABLE`, then atomic full replace |
| `mart.marketing_funnel_task_contract` | one candidate `(task_id, contract_id)` | `CREATE TABLE`, then atomic full replace |

No existing CRM, revenue, 1C, Power BI, plan, schedule or incremental object
is altered. Before initial DDL the runner must prove both target relations are
absent. `REVOKE ALL ... FROM PUBLIC` is part of the DDL. No index beyond
primary/unique keys is proposed without an actual post-load plan.

## Immutable SQL and rollback

- DDL: [marketing_funnel_reviewed_plan.sql](../../sql/marts/marketing_funnel_reviewed_plan.sql)
- source extracts: [marketing_funnel_source_extract.sql](../../sql/marts/marketing_funnel_source_extract.sql)
- reconciliation: [marketing_funnel_reconciliation.sql](../../sql/tests/marketing_funnel_reconciliation.sql)
- rollback: [marketing_funnel_rollback.sql](../../sql/marts/marketing_funnel_rollback.sql)

Rollback is a separately reviewed `DROP TABLE` transaction and is not
automatic. It is allowed only when these two objects were created by this
package and no Power BI consumer has been switched.

`MF-DIAG-001—002` found 19 groups of byte-for-byte identical bridge rows in
the first source snapshot. The reviewed bridge extract therefore applies
`DISTINCT` to its complete projected row: it removes only those technical
repeats, preserves the confirmed `(task_id, contract_id)` grain and changes
neither BR-003 nor BR-020.

`MF-FIX-002` proved that the previous lower bound `activation_date >=
2024-01-01` excluded the pre-month contract history required by the approved
current-PBIT control. The reviewed bridge extract keeps every non-null
activation date for a BR-003-scoped task; BR-020 remains a separate flag and
continues to set `contract_count`. On the independent 2025-07 control this
restores `66 404 - 27 319 - 15 221 = 23 864` exactly.

Accordingly, `MF-R04` guards that any historic bridge row remains
non-converting under BR-020 rather than incorrectly forbidding the history
that `MF-R05` requires.

The runner emits non-sensitive progress markers for target transaction,
lock, delete, each binary COPY (rows and bytes), every reconciliation control
and commit. This telemetry changes no source predicate, target SQL or result;
it makes a future VM-2 wait attributable before any intervention.

## Atomic load design

1. On VM-1 start one `REPEATABLE READ READ ONLY` transaction, calculate the
   confirmed BR-003 horizon and binary-COPY the two source queries. In August
   2026 it is `[2025-01-01, 2027-01-01)`.
2. Capture the two COPY row totals as immutable run controls. The source
   transaction transfers no raw registry, documents, PII name or phone.
3. On VM-2 begin one transaction; for a rebuild lock both target tables,
   delete child then parent, COPY task then bridge, run all reconciliation
   statements, and commit only when every expected value passes. A failure
   rolls back the entire target transaction.
4. Rerun the full sequence in a new source snapshot. It passes only when the
   new source COPY totals equal the corresponding target totals and every
   target control remains zero. A live-source delta is recorded, never hidden
   by comparing two different snapshots as if they were identical.

## Acceptance controls

`MF-R01`—`MF-R06` cover source/target transport totals, task and bridge keys,
required fields, BR-020, BR-003, the independent current-PBIT month control
and public access. The fixed independent PBIT control is:

`66 404 tasks − 27 319 cancelled − 15 221 activated contract-clients = 23 864`

for 2025-07-01. A target mismatch is `FAIL`, not a tolerance candidate. All
other accepted source and target differences are exactly zero.

## Required user authorization before execution

Approval must name this document and all four immutable SQL files, allow the
two listed `CREATE TABLE` statements, the full-rebuild `DELETE + COPY` within
one target transaction, source read-only extraction, reconciliation, one
rerun and the documented rollback boundary. Until then all statements remain
`NOT_EXECUTED`.
