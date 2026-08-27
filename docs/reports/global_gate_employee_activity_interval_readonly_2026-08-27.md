# Global gate review and «Загрузка сотрудников»: read-only authorization

- Date: 2026-08-27
- Package: `global_gate_employee_activity_interval_readonly_2026-08-27`
- Stage: `STAGE_3_GLOBAL_REVIEW` followed by `STAGE_2_SERVER_VALIDATION`
- Basis: the user's explicit approval on 2026-08-27 to close all questions and
  create `mart.employee_activity_interval`.

## Authorized scope

1. Perform a complete read-only audit of the contract-report ledger, global
   unresolved-question register, data-product inventory, active package state,
   existing Stage 3 evidence and global gate. Reconcile stale historical text
   only to primary, current evidence; do not silently turn a business decision
   into a closed control.
2. When the audit has documented the permitted gate state, perform the
   accumulated read-only Stage 2 controls for `employee_workload`, including
   EW-V01--EW-V07: event keys, source states, `VT4352` cardinality,
   coupon/duty overlap, SCUD-to-employee cardinality, source-to-reuse totals
   and historical employment attribution. Use short fresh read-only sessions
   with the shared bounded retry policy and retain SQL, expected result,
   snapshot and actual result.
3. Update mapping, contract, ADR, business rules, missing-source register,
   evidence and checkpoint ledger with only confirmed facts. Prepare the exact
   immutable Stage 3 DDL, extract, loader, rollback, reconciliation and measured
   plan specification only after all source conditions are closed.

## Boundaries

This authorization permits no DDL, DML, `COPY`, target-table creation, Power
BI changes, source changes, external-file review or unreviewed business-rule
changes. A subsequent physical admission requires the reviewed exact SQL plan,
named target operations and rollback to be shown and approved before execution.

## Closure criterion

The global gate has a documented current decision; every EW-V01--EW-V07 check
is `PASS`, `BLOCKED` or `DECISION_REQUIRED` with reproducible evidence; and an
immutable Stage 3 plan either has no unresolved mapping/key/grain/state issue
or identifies the one exact user decision that prevents delivery.

## Global audit result

The audit used the checkpoint ledger and its linked primary evidence as the
current authority. The older `global_unresolved_questions_register_2026-08-14`
is a historical discovery register: its `OPEN`, `VALIDATION_REQUIRED` and
`DECISION_REQUIRED` labels were checked against later checkpoint/authorization
evidence and do not independently reopen a source control.

| Check | Actual | Status |
|---|---:|---|
| Ledger checkpoints | 73 total: 72 `CLOSED_CHECKPOINT`, 1 current audit | PASS |
| Unique report IDs with a closed checkpoint | 43 | PASS |
| Duplicate `(report_id, stage)` ledger rows | 0 | PASS |
| Exact `docs/` and `sql/` evidence paths extracted from ledger | all present | PASS |
| Catalogued `mart.*` products | 41: 30 implemented/validated, 11 explicitly designed/deferred | PASS |
| Autonomous selections unrelated to this audit | 0 | PASS |

No source, target or Power BI action was taken. The audit establishes that
historical wording is not an unrecorded technical blocker, but it does not
invent an `employee_activity_interval` event key, overlap policy, SCUD
attribution or state rule. The user must now make the required explicit
post-review decision on the global gate before a new Stage 2 source package is
opened. Therefore the gate moves to `CLOSED_PENDING_NEXT_APPROVAL`.
