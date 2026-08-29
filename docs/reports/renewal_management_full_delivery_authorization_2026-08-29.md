# RM-FULL-DELIVERY-001: authorization record

Date: 2026-08-29.

## User authorization

The user explicitly authorized completing Stage 2 and Stage 3 for
`mart.renewal_management_contract` without intermediate approvals.

## Scope and autonomy boundary

1. Run all outstanding read-only Stage-2 controls for the documented current
   Power BI/M/DAX logic: cohort and exclusions, same-client/first-start
   next-contract selection, source states, contract key/code, price and visit
   paths, and rating/tenure/interaction cardinality.
2. Record executed SQL, source snapshot, outcomes and evidence; update mapping,
   ADR, data contract, source metadata and the ledger.  Preserve any observed
   current behavior under BR-018; do not silently introduce a new business rule.
3. If and only if all implementation-critical semantics are confirmed, prepare
   an immutable Stage-3 set (mapping, ADR, source extract, independent controls,
   DDL, loader and reconciliation), measure its required source-plan ladder,
   then create and atomically load `mart.renewal_management_contract` with an
   initial load and a rerun.
4. DDL/DML are limited to the new target object and its transaction-scoped
   temporary load state.  Source 1C stays read-only; no raw register replica,
   unbounded transport, source index, Power BI change, or incremental-SLA claim
   is in scope.

## Closure criterion

Stage 2 closes only when each implementation blocker is either confirmed with
full-population evidence or recorded as `BLOCKER`.  Stage 3 closes only after
the immutable SQL set, sample and accepted full source plans, independent
expected controls, atomic initial load, reconciliation, target read plan and
atomic rerun are all evidenced.  A remaining unresolved material fact stops
the package rather than being hidden in SQL.

## Outcome

Closure criterion met on 2026-08-29. The initial load, atomic reruns,
RM-R01--RM-R05, target plan and clean 131.40-second full-rebuild baseline are
recorded in
`docs/reports/renewal_management_stage3_product_admission_execution_2026-08-29.md`.
