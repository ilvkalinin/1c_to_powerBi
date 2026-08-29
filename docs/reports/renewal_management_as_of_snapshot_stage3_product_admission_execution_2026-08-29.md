# RM-ASOF-S3-LOAD-001—006: execution — forward observation history

Дата: 2026-08-29. Target object:
`mart.renewal_management_contract_observation`.

## Scope and result

Only the approved VM-2 local derived-state object was created. It stores no
client name, phone, birth date, price, visit or raw 1C rows. It is not a
retrospective reconstruction of the 2025 source state; the first baseline is a
forward observation at `2026-08-29 15:51:34.090788+03`.

Initial transaction committed:

| Metric | Result |
|---|---:|
| independent parent expected rows / distinct contract IDs | 240,967 / 240,967 |
| inserted `BASELINE` rows | 240,967 |
| inserted `CHANGED` / `REMOVED` rows | 0 / 0 |
| RMO-R01—RMO-R05 before commit | all `PASS` |
| initial runner wall time | 23.7 s |
| atomic `--append` rerun observed_at | 2026-08-29 15:52:30.611751+03 |
| rerun inserted rows | 0 |
| rerun RMO-R01—RMO-R05 | all `PASS` |

The three earlier initial attempts were rolled back before commit: two
psycopg parameter-binding defects and one missing `FROM` in RMO-R05. The
runner's exception path executed `ROLLBACK`; the successful `--apply` still
required an absent relation and committed the only initial object/state.

## Reconciliation

[independent parent controls](../../sql/marts/renewal_management_contract_observation_source_controls.sql)
recorded the expected count, key count, min/max end dates and mandatory parent
fields without using `state_hash`. In the same `REPEATABLE READ` target
transaction, [RMO-R01—RMO-R05](../../sql/tests/renewal_management_contract_observation_reconciliation.sql)
confirmed latest-state count, composite-key uniqueness, hash/null/kind/date
contracts, exact parent-state equivalence, tombstone rules and no PUBLIC
`SELECT` grant. The rerun used its own fresh transaction snapshot.

## Performance evidence

The approved parent projection ladder completed before DDL/DML, without spill:
1 month 6,124 rows / 298.980 ms; 2 months 9,729 / 126.420 ms; 3 months
13,244 / 196.198 ms; 6 months 29,187 / 289.648 ms; full current parent
240,967 / 1,704.524 ms. The full plan was a sequential scan with 5,978 hit
and 7,254 read blocks, zero temp blocks. This is a full current-state scan
baseline only, not an incremental SLA.

Initial relation size is 110,239,744 bytes. The first as-of `DISTINCT ON`
read measured 2,755.651 ms and spilled 1,946/1,951 temp blocks. An equal-result
`MAX(observed_at)` plus composite-PK join returned the same 240,967 current
contracts in 460.592 ms; it also spilled 6,187/6,187 temp blocks but is the
chosen future-query shape. No index, planner setting or extra target object was
created because the approved package did not need one and no Power BI workload
SLA is established.

## Boundary and next trigger

Power BI, schedule, retention deletion policy, raw source replication and
retrospective source-history claims remain unchanged/excluded. The fact will
record later changes only when the approved loader is invoked after a
successful parent mart refresh. Any scheduling, Power BI integration, index
change, retention policy or authoritative historical source is a separate
package.
