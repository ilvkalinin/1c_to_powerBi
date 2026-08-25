# Read-only audit: child-package coverage in the client-base family

- Date: 2026-08-25
- Package: `client_base_family_package_coverage_2026-08-25`
- Stage: `STAGE_2_SERVER_VALIDATION`
- Authorization: explicit user request 2026-08-25 to check every mart that
  contains client base and ensure packages are included.

## Scope

Read-only coverage and reuse review of the three client-base facts:
`mart.client_base_daily`, `mart.client_base_snapshot`, and
`mart.client_base_retention`. The audit distinguishes a physical client-base
source universe from downstream marts that only consume
`mart.client_base_daily` as a denominator. It verifies BR-037/BR-038 lineage,
physical implementation state, source SQL, target contract and consumer reuse.

## Boundaries

No DDL, DML, Power BI, source changes, refresh, or creation of mart objects.
Absent physical implementations are documented only in
`docs/source_metadata/missing_source_objects.md`. No external Excel or Power
Query work is in scope.

## Closure

Every client-base family fact has a CONFIRMED coverage status: implemented
facts have BR-037/BR-038 package lineage and independent controls; deferred
facts are explicitly marked as package-aware design requirements rather than
silently treated as covered. The report lists zero unknown in-scope physical
facts or a precise BLOCKER, and Power BI remains unchanged.
