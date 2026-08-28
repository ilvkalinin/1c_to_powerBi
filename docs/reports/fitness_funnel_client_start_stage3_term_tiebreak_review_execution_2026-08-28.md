# Stage 3 technical review: client-start tie-break ranks

Status: `VALIDATED`. Package:
`fitness_funnel_client_start_stage3_term_tiebreak_review_2026-08-28`.

## Scope and operations

This review implements only the user-approved read-only scope in
[authorization](fitness_funnel_client_start_stage3_term_tiebreak_review_authorization_2026-08-28.md).
All source checks used fresh `REPEATABLE READ, READ ONLY` sessions with the
project retry helper and `SET LOCAL work_mem = '64MB'`. No source object,
target connection, DDL, DML, COPY, transport, Power BI artifact or SQL runner
was changed.

## Independent full-horizon rank controls

The approved horizon is `[2024-01-01, 2026-08-28)`. The final ranking is
`Fld674 DESC`, `Fld693 DESC`, `Fld670 ASC`, then `contract_ref ASC` as the
user-approved stable arbitrary fallback.

| Control | Expected | Actual | Status |
|---|---:|---:|---|
| eligible contract rows | observed | 231,645 | PASS observed |
| selected client-date cohorts | one per cohort after grouping | 231,490 | PASS |
| winner groups with more than one source contract | observed | 35 | PASS observed |
| selected rows per client-date cohort | 1 | 1 | PASS |
| selected cohort rows | observed | 231,490 | PASS |
| selected null/duplicate-key deviations | 0 | 0 | PASS |
| residual business-rank attribute conflicts before technical fallback | observed | 4 | PASS observed |

The final `row_number` selector uses the stable technical fallback only after
the three user-approved business ranks, preserves one client-date row and has
no target-key collision.

## Reproducible example

Client code `001338713` has start date `2025-01-26` and two eligible contracts
with the same purchase timestamp `2023-06-30`, `Fld693 = 14`, and actual
interval 13 calendar days. Both are `Ex`, but their access clubs differ:
contracts `ВР00087207` and `ФК00053691`. Neither approved rank distinguishes
them. Client code is included at the user's request; no name, phone or other
PII is recorded.

## Revised immutable set and plan

The extract, controls and guarded runner now implement BR-048. Full controls:
231,645 eligible contracts; 231,490 selected cohorts; 155 collapsed contracts;
selected nulls, duplicate keys and future dates = 0. On `[2026-08-01,2026-08-08)`
the exact revised extract returned 1,442 rows in 58.973 ms (planning 4.396 ms),
shared hit/read 7,807/0 and temp 0/0. Static retry-policy check passed. No
target operation occurred; a new explicit physical admission is required.
