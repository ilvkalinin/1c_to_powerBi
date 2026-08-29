# RM-S3-ADMISSION-001: `mart.renewal_management_contract`

Status: `VALIDATED / initial load, atomic reruns and final clean timed rerun passed`.

The user authorization recorded in
`docs/reports/renewal_management_full_delivery_authorization_2026-08-29.md`
covers this immutable Stage-3 set. The reviewed SQL set has not changed.

## Reviewed set

| Role | File |
|---|---|
| source-to-target mapping | `docs/mappings/renewal_management.md` |
| grain and decision | `docs/adr/0007-renewal-management-contract-mart.md` and BR-050 |
| Power BI contract | `docs/data_contracts/renewal_management.md` |
| source extract | `sql/marts/renewal_management_contract_source_extract.sql` |
| independent expected controls | `sql/marts/renewal_management_contract_source_controls.sql` |
| target DDL | `sql/marts/renewal_management_contract_ddl.sql` |
| target reconciliation | `sql/tests/renewal_management_contract_reconciliation.sql` |
| transactional runner | `scripts/load_renewal_management_contract.py` |

## Exact scope and safety boundary

- New target object only: `mart.renewal_management_contract`.
- One target row per retained source membership contract; primary key is
  `expiring_contract_id`; `expiring_contract_code` is also unique.
- Current M horizon is exact: end date `> 2024-01-01` through the last day of
  the month six months ahead. On 2026-08-29 this is
  `[2024-01-02, 2027-02-01)`.
- Source stays `REPEATABLE READ, READ ONLY`; no 1С DDL/DML/index or raw copy.
- One bounded, derived-column binary COPY buffer has a 1 GiB disk cap and is
  automatically removed. Source controls and extract run in the same source
  snapshot before the target connection begins.
- Initial `CREATE TABLE + COPY + reconciliation` is one target transaction.
  Any failure rolls it back. After commit, automatic `DROP` is forbidden.
- Rebuild uses a transaction-scoped advisory lock and transactional `TRUNCATE`;
  the required rerun measures its blocking/time. This is a full rebuild, not
  an incremental refresh and has no one-minute SLA claim.
- Power BI, Excel and source schemas are out of scope.

## Performance admission

The required exact source-plan ladder is recorded in
`renewal_management_stage3_technical_scope_2026-08-29.md`. The accepted full
baseline returned 240,969 rows in 89.433 seconds. It had no timeout. The
single full derived output must pass the runner's explicitly checked 1 GiB
transport cap; its actual size is checked before any target transaction.

## Acceptance and rollback

Before target COPY, the independent control path supplies row/distinct-key
counts, end-date bounds, price and visit totals, and renewal counters. The
runner requires its source `COPY` row count to equal that control in the same
snapshot. Before commit it requires RM-R01--RM-R05: aggregate reconciliation,
keys/required values/horizon, renewal formulas, non-additive formulas and the
`PUBLIC SELECT` boundary. It then measures a target read plan and runs one
atomic full rerun before acceptance.

## Execution evidence to date

- The initial `CREATE TABLE + COPY + reconciliation` committed successfully.
- One subsequent atomic full rebuild also committed successfully. In each run
  source controls and the exact COPY extract were executed in one read-only
  snapshot; the current snapshot control was 240,968 rows and 240,968 distinct
  expiring-contract IDs. RM-R01--RM-R05 passed before commit.
- The recorded post-rerun target read plan returned 240,968 rows in 209.857 ms;
  `pg_total_relation_size(mart.renewal_management_contract)` was 136,839,168
  bytes at that check.
- A later third, time-captured rebuild attempt completed its source COPY but
  the VM-2 connection closed during target COPY after transactional `TRUNCATE`.
  The transaction did not commit; it cannot replace the previously committed
  version. This is a target-connection incident, not a reconciliation
  deviation. A following one-shot, read-only reconnect/count check with a
  five-second connection limit also produced no response and was terminated;
  it did not execute any target SQL. This is a technical `BLOCKED` state. One
  successful timed atomic rerun remains required after VM-2 is reachable again.

- On a resumed attempt, raw TCP and a short PostgreSQL handshake probe both
  succeeded, but the approved time-captured rerun again hung while opening the
  later target session. Its source controls and exact source COPY completed in
  one read-only snapshot with 240,967 rows and a 127,375,791-byte derived
  buffer. There was no `TARGET_TRUNCATE_COMPLETE`, so no VM-2 transaction or
  target SQL began; the runner was terminated and its temporary buffer cleaned
  up. The blocker is therefore intermittent VM-2 PostgreSQL session admission,
  not source performance, row reconciliation, or rollback.

The blocking sessions were subsequently identified as the previous interrupted
COPY plus four stale self-owned diagnostics, rolled back/terminated, and the
final clean rerun committed with RM-R01--RM-R05 passing in 131.40 s. Final
target scan and size evidence are in
`renewal_management_stage3_product_admission_execution_2026-08-29.md`.
