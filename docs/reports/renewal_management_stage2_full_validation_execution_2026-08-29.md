# RM-FULL-DELIVERY-001: Stage 2 execution

Date: 2026-08-29.  Status: `VALIDATION_FAILED / BLOCKED`.

This execution used only fresh `REPEATABLE READ, READ ONLY` source sessions
through `connect_with_retry`. It made no source or target write, DDL, COPY,
Power BI, or target-permission change. Exact SQL is
[`renewal_management_stage2_full_2026-08-29.sql`](../source_metadata/validation_sql/renewal_management_stage2_full_2026-08-29.sql).

## Expected controls and results

| Control | Expected before execution | Actual | Status |
|---|---|---:|---|
| RM-S2-01 cohort/key/exclusions | one retained row per source contract | 240,971 rows = 240,971 IDs; duplicate rows 0 | PASS |
| RM-S2-02 old→next | zero ties at current minimum next start | 93 tie groups; 189 tied candidates; maximum 5; 2 selected candidates are marked | **FAIL / BLOCKER** |
| RM-S2-03 code | no cohort code maps to multiple IDs | 0 duplicate groups | PASS |
| RM-S2-04 rating/tenure | one latest row per client | 0 rating and 0 tenure tie groups | PASS |
| RM-S2-05 latest interaction | zero ties at current maximum interaction timestamp | 96 tie groups; 198 tied rows; maximum 5 | **FAIL / BLOCKER** |
| RM-S2-06 price | one physical register key; expose state/orphans | 9,159,712 rows = keys; 9,631 inactive; 2,845,349 contract orphans | PASS as observation |
| RM-S2-07 visits | code grouping does not merge contract IDs | 2,889,583 rows = technical keys; 116,741 IDs; 0 duplicate-code groups | PASS |
| RM-S2-08 types | all required fields exist | 16 / 16 fields found | PASS |

RM-S2-01 also observed 129 `Document332` rows (114 posted) and 1,685
`Document287` rows (1,564 posted; 106 marked) in the pre-exclusion population.
The current M filters posted `Document332` but has no `Document287` state
predicate; this current behavior is preserved and not reinterpreted.

## Performance evidence

The first full-set formulation of RM-S2-02 timed out at its 300-second,
source-local limit. Catalog evidence showed `_reference59` has approximately
2,085,677 rows and an existing client-indexed access path. The control was
rewritten without changing a single legacy predicate: for each cohort row it
uses the current same-client `ORDER BY _Fld671 LIMIT 1` path and separately
counts candidates at that selected minimum start. The accepted control ran in
12.708 seconds. No timeout was raised and no source index or setting changed.

## Blocking facts

1. The current Power Query selects the next contract by `ORDER BY start_date`
   only. Ninety-three full-population cohorts have two to five eligible next
   contracts at the minimum date. PostgreSQL may select any tied row, so a
   physical one-row contract mart cannot claim deterministic reproduction.
2. The current Power Query's `ROW_NUMBER()` for latest eligible interaction
   orders only by interaction datetime. Ninety-six clients have two to five
   rows at that maximum datetime. Its selected interaction type/stage/fail
   reason is likewise nondeterministic.

No technical tie-break is inferred from identifiers, marked status or row
order. Choosing one changes a report attribute and potentially Renew/type or
CRM detail under BR-018; it requires a new explicit business decision. The
authorised package therefore stops before Stage 3. The existing target
`mart.contract_usage` remains out of scope because its grain and frozen visit
semantics are not this report's current-state contract row.
