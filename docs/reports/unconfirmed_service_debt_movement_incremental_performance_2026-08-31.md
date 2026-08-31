# Incremental performance evidence: `unconfirmed_service_debt_movement`

Status: `VALIDATION_IN_PROGRESS / SOURCE_PLAN_MEASURED`.

Measured from the exact configured source extract by
`scripts/load_unconfirmed_service_debt_movement_incremental.py --plan-only` on
2026-08-31. No target DML, transport, target diff or reconciliation was run.

| Source window | Rows | Execution time | Shared hit | Shared read | Temp read/write |
|---|---:|---:|---:|---:|---:|
| 2026-06-01 .. 2026-07-01 | 59,890 | 623.748 ms | 417,489 | 0 | 0 / 0 |
| 2026-06-01 .. 2026-08-01 | 105,595 | 794.322 ms | 352,682 | 0 | 0 / 0 |
| 2026-06-01 .. 2026-08-31 | 149,454 | 1,071.720 ms | 493,002 | 0 | 0 / 0 |

The observed source-plan ladder has no measured disk reads or temporary spill.
It is not an end-to-end refresh measurement and does not establish the
configured incremental SLA. Remaining checks: source transport, target stage,
window replacement, reconciliation and target read plan after an approved
runtime run.
