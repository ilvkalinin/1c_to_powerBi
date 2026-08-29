# RM-ASOF-S3-LOAD-001—006: `mart.renewal_management_contract_observation`

Статус: `VALIDATED / admission complete`.

## Immutable reviewed set

| Role | Artifact |
|---|---|
| mapping | [source-to-target mapping](../mappings/renewal_management_as_of_snapshot.md) |
| ADR | [ADR-0033](../adr/0033-renewal-management-observation-history.md) |
| data contract | [data contract](../data_contracts/renewal_management_as_of_snapshot.md) |
| source projection | [PII-free parent extract](../../sql/marts/renewal_management_contract_observation_extract.sql) |
| target DDL | [DDL](../../sql/marts/renewal_management_contract_observation_ddl.sql) |
| delta DML | [append SQL](../../sql/marts/renewal_management_contract_observation_append.sql) |
| independent expected | [source controls](../../sql/marts/renewal_management_contract_observation_source_controls.sql) |
| target tests | [reconciliation](../../sql/tests/renewal_management_contract_observation_reconciliation.sql) |
| runner | [loader](../../scripts/load_renewal_management_contract_observation.py) |
| plan runner | [measurement runner](../../scripts/measure_renewal_management_contract_observation_source.py) |

## Object and transaction boundary

One row is `expiring_contract_id × observed_at`, exactly one `BASELINE`,
`CHANGED`, or `REMOVED` version per contract/run. The new table contains only
the current mart's PII-free observation state. It does not copy `Reference59`,
`Reference67`, visits, interaction rows or any other VM-1 raw source.

Initial approved operations are, in one VM-2 `REPEATABLE READ` transaction
under a transaction-scoped advisory lock:

1. `CREATE TABLE mart.renewal_management_contract_observation` and `REVOKE ALL
   ... FROM PUBLIC` from the reviewed DDL;
2. read independent parent controls;
3. append `BASELINE` rows from the current parent mart;
4. run RMO-R01—RMO-R05 before `COMMIT`.

On any error the runner rolls back; it never auto-drops a committed object.
The approved rerun is `--append`: it writes only changed/reappeared states and
one tombstone per newly absent parent contract. It is not a full rebuild or an
incremental SLA.

## Performance evidence before DDL/DML

Exact parent projection was measured read-only with
`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`, no transport in parallel.

| Window ending 2026-09-01 | Rows | ms | top node | hit/read blocks | temp |
|---|---:|---:|---|---:|---:|
| 1 month | 6,124 | 298.980 | Gather | 5,414 / 7,818 | 0 / 0 |
| 2 months | 9,729 | 126.420 | Gather | 5,696 / 7,536 | 0 / 0 |
| 3 months | 13,244 | 196.198 | Seq Scan | 5,790 / 7,442 | 0 / 0 |
| 6 months | 29,187 | 289.648 | Seq Scan | 5,884 / 7,348 | 0 / 0 |
| full current mart `[2024-01-01, 2027-02-01)` | 240,967 | 1,704.524 | Seq Scan | 5,978 / 7,254 | 0 / 0 |

No spill, VPN or connection failure occurred. A sequential scan is accepted:
the full parent fact is intentionally projected once, and the target append is
local VM-2-to-VM-2 SQL rather than a source transport. No source index, target
helper table, session GUC or additional index is proposed.

## Reconciliation and acceptance

Independent expected controls count current parent rows/distinct IDs/date
range/mandatory fields without using the state-hash formula. Before commit,
RMO-R01 compares latest nonremoved observation count to that independent
expected; RMO-R02—RMO-R05 cover key/hash/null/kind/date, exact latest-state
projection, tombstone rules and PUBLIC access. The same controls run on an
atomic append rerun captured from its own transaction snapshot.

After commit, measure target relation size and a latest-as-of read plan. Power
BI remains unchanged: connection, relationships, retention and schedule are
not delivered here. The first observation is a forward baseline only; no row
is described as a reconstructed 2025 source snapshot.

## Checklist

- [x] Immutable reviewed set and exact hazardous operations are recorded.
- [x] Every DDL column has mapping, type, null policy and test.
- [x] Grain/key/state transition rules are confirmed; retrospective claims are excluded.
- [x] Progressive sample ladder and full parent plan are measured before DDL/DML.
- [x] VM-2 retry policy uses common initial + five `OperationalError` retries.
- [x] No VM-1/VPN transport, raw staging or temporary file is needed.
- [x] Advisory lock, atomic transaction and rollback path are implemented.
- [x] Independent expected controls and in-transaction reconciliation are defined.
- [x] Initial load, atomic rerun, target plan/size and final acceptance evidence:
      [execution](renewal_management_as_of_snapshot_stage3_product_admission_execution_2026-08-29.md).
