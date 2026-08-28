# Technical SQL review: `mart.contract_usage`

Статус: `REVIEWED / PHYSICAL ADMISSION BLOCKED`.

Пакет относится только к отчёту № 17 `%Renew` (`renew_contract_usage`). Он
сохраняет first-release current-M domain: fixed legacy year window, current
joins and `COUNT(*)`; не добавляет фильтр `Active`, `Posted`, `Marked`,
interval-фильтр или методическую замену `Fld693` по BR-018. Power BI, Excel и
VM-2 в пакете не изменялись.

## Immutable reviewed set

- [mapping](../mappings/renew_contract_usage.md),
  [data contract](../data_contracts/renew_contract_usage.md) and
  [ADR-0006](../adr/0006-renew-contract-usage.md);
- [source extract](../../sql/marts/contract_usage_source_extract.sql);
- [independent source controls](../../sql/marts/contract_usage_source_controls.sql);
- [DDL](../../sql/marts/contract_usage_ddl.sql);
- [future atomic runner](../../scripts/load_contract_usage.py);
- [target reconciliation](../../sql/tests/contract_usage_reconciliation.sql).

The target grain is one contract ID. `contract_id` is the target-safe text
representation `encode(Reference59.ID, 'hex')`; `contract_code` remains the
Power BI join candidate and is protected by a target `UNIQUE` constraint only
after the full CU-S02 control passes. The extract returns only the contract IDs
that appear in current M output; it does not invent zero-visit contracts.

## Representative source evidence — CU-TR-001

Source session: fresh `REPEATABLE READ, READ ONLY`; no target connection.
Exact extract and independent controls used `[2026-08-17, 2026-08-24)`.

| Control / metric | Actual | Status |
|---|---:|---|
| CU-S01 legacy rows / technical keys / documents | 69,562 / 69,562 / 69,562 | PASS sample |
| CU-S01 inactive / unposted / marked rows | 0 / 0 / 0 | OBSERVED; no new filter |
| CU-S01 polymorphic pairs | `08/0000003b` (one pair) | PASS sample; full-window pending |
| CU-S02 target-grain code groups / duplicate groups | 31,788 / 0 | PASS sample; full-window pending |
| CU-S03 target-grain rows / visit sum | 31,788 / 69,562 | PASS sample |
| CU-S03 null dates / reversed intervals / null terms / negative terms | 0 / 0 / 0 / 0 | PASS sample |
| Source start-date minimum / end-date maximum | `0001-01-01` / `2300-03-12` | OBSERVED; source values retained |

## Actual-plan review

The exact extract was measured twice on the same bounded horizon. The
node-level run is the performance evidence: planning 7.362 ms; execution
1,505.871 ms; 31,788 output rows; shared hit 1,060,722; shared read 0; temp
read/write 0.

`_accumrg7575` uses existing `_accumrg7575_5` period index (81,789 source
rows; 134.692 ms). The remaining joins are point lookups: `_document325` PK
index (81,638 loops at 0.002 ms), `_reference141x1` index-only lookup (75,638
loops at 0.005 ms) and `_reference59` PK index (70,611 loops at 0.004 ms).
The final sort and aggregation have no spill. No measured evidence supports a
different join order, session-local planner setting or an index proposal on
read-only 1C. This is an accepted short-sample baseline, not a full-range
baseline or daily SLA claim.

## Delivery design

The future runner has no default legacy window, finalization cutoff or transfer
cap. Its physical-admission invocation must provide all four values explicitly:
`legacy_start`, `legacy_end`, `mutable_from_month`, `max_transfer_bytes`.
It captures independent controls then writes only derived target columns into a
bounded binary temporary file. VM-1 closes before the target transaction opens.
The target transaction takes an advisory lock, loads a temporary stage, updates
newly finalizing rows, replaces only the mutable section, reconciles before
commit and rolls back on any error. It never creates a raw 1C replica.

## Blocker before physical admission

`is_finalized` / `finalized_month` need a named operational authority that
provides `mutable_from_month` at each close. No physical source field expresses
the close boundary, and the project prohibition on Excel analysis means it must
not be inferred from an Excel snapshot. Until this authority and the initial
cutoff are supplied, DDL/DML/COPY, target reconciliation, full-range plan,
initial load and rerun remain `NOT_EXECUTED`.

The eventual physical package must run CU-S01--CU-S03 on the full approved
legacy window before COPY, set a measured transfer cap, then collect a
full-range source baseline, target read-plan, initial-load reconciliation and
atomic rerun evidence. Full rebuild may not be represented as incremental SLA.
