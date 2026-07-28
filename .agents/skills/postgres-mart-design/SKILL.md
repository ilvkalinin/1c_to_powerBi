---
name: postgres-mart-design
description: Design minimal PostgreSQL analytical marts for Power BI from an approved source-to-target mapping. Use when choosing grain, facts, dimensions, keys, storage object, layering, refresh strategy, or shared business logic.
---

# PostgreSQL mart design

## Entry gate

Require approved report requirements and source-to-target mapping. Stop at a named `BLOCKER` if grain, keys, essential joins or business formulas are unresolved.

## Workflow

1. State the exact grain of one row and reject mixed grains.
2. Identify logical keys, facts, dimensions and reuse across reports.
3. Compare:
   - `mart` directly over the source;
   - `staging + mart`;
   - `staging + core + mart`.
4. Choose the fewest layers that avoid duplicated business logic, meet measured performance needs and remain maintainable.
5. Compare a view, materialized view and physical table using freshness SLA, cost, volumes, correction/deletion behavior and refresh evidence.
6. Choose full rebuild, change-date increment, identifier increment, sliding window, mutable-period recalculation or hybrid loading only when source behavior supports it.
7. Record context, options, decision, reasons, consequences, risks and review triggers in `docs/adr/`.
8. Hand the approved design to the data-contract and implementation workflows.

Do not fabricate a watermark, index, layer or technical log. Do not choose materialization only because it might be faster. Preserve interactive filter-dependent logic for DAX when appropriate.

## Output

Return one recommended architecture, not competing SQL implementations. Include grain, keys, object type, layer diagram in prose, refresh strategy, Power BI boundary, unresolved decisions and an ADR.

