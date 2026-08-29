# RM-ASOF-S3-LOAD-001—006: authorization — forward observation history

Дата: 2026-08-29.

## User authority

Пользователь явно подтвердил самостоятельный Stage 3 admission-пакет после
RM-ASOF-S2-001. Scope — только forward append-only observation для
`mart.renewal_management_contract_observation`; никаких claims о source state
2025 до первого observation не допускается.

## Permitted scope

1. Подготовить immutable mapping/ADR/data contract и exact reviewed SQL для
   одного нового target object, loader и reconciliation.
2. Выполнить read-only sample `EXPLAIN (ANALYZE, BUFFERS)` exact derived
   parent-mart extract до DDL/DML; это VM-2-to-VM-2 target-derived load, без
   VM-1 source extract, raw-table copy или межсерверного transport.
3. В одной target transaction под advisory lock выполнить только `CREATE TABLE
   mart.renewal_management_contract_observation`, `REVOKE ALL ... FROM PUBLIC`
   и initial append from `mart.renewal_management_contract`; failure before
   commit means `ROLLBACK`. No automatic post-commit `DROP`.
4. Выполнить independent expected controls before insert, target reconciliation
   before commit, one atomic rerun, post-load target plan/size and record
   timings. Power BI connection, model, schedule, retention policy and raw
   replication are excluded.

## Closure

Exact implementation/evidence links, confirmed grain and state transition
rules, measured representative source plan, source-to-target reconciliation,
atomic rerun, target read plan/size and Power BI boundary are recorded. Any
material deviation from the listed object/operations is a `BLOCKER`.
