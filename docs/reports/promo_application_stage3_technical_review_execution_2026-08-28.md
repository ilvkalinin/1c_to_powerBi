# Stage 3 technical SQL review: mart.promo_application

Status: VALIDATED for local technical design; physical delivery remains NOT
APPROVED. Package: promo_application_stage3_technical_review_2026-08-28.

## Semantic decision

BR-046 is confirmed by explicit user decision. First release grain is the
current post-M report row from two branches, retaining current branch-specific
aggregation and observed multiplicity. It intentionally does not invent a
unique source-line business key. report_row_id is a technical ordinal for one
atomic full snapshot only.

Exact PBI source: Pbit_old/Отчет по промокодам.pbit, SHA-256
79005ec09a6698887b7e341d5b2b16a902fdce7b78e992888bf2e0129a409956.
No Power BI, M, DAX, source schema/data, target schema/data, COPY, or transport
has been changed in this package.

## Source plan evidence

Environment: live gymdb, gymdb_readonly, fresh REPEATABLE READ READ ONLY
transactions on 2026-08-28. Candidate SQL:
sql/marts/promo_application_source_extract.sql. The historic exact query timed
out in the 30 s safe one-day budget. Candidate changes only execution shape:
final-date predicate reaches branch inputs and shared 45-day outcome sets are
materialized once.

| Window | Rows | Execution ms | Shared hit/read | Temp r/w |
|---|---:|---:|---:|---:|
| 1 day, 2026-06-01 | 180 | 1294.555 | 1027659 / 0 | 0 / 0 |
| 2 days | 441 | 1269.892 | 1063878 / 0 | 0 / 0 |
| 7 days | 1632 | 1449.187 | 1219792 / 0 | 0 / 0 |
| 30 days | 10352 | 2430.484 | 2052764 / 0 | 0 / 0 |
| 2 months | 18673 | 4717.476 | 3152879 / 87 | 0 / 0 |
| 3 months | 23789 | 6148.652 | 4032420 / 61 | 3556 / 3556 |
| 6 months | 38507 | 10190.724 | 6814430 / 212 | 3971 / 3971 |
| full BR-003 2025-01-01 to 2026-08-29 | 132801 | 39236.433 | 16678651 / 0 | 68767 / 62606 |

Full plan planning time was 51.786 ms. A separate full source control returned
132801 total, 35028 promo_gift, 97773 discount, min/max date
2025-01-02/2026-08-28, discount sum 861840283.61, price sum
2156159943.92000, and zero null/empty client keys or null dates.

## Admission constraints

This establishes only the full-rebuild source baseline, not daily incremental
SLA evidence. The next package must explicitly approve immutable files, target
connection, atomic DDL/load, source-first temporary transport, reconciliation,
target read-plan, rollback and rerun. Because source full baseline exceeds one
minute, it cannot be represented as a one-minute refresh. Source-first disk
cap and batch measurements are NOT EXECUTED.
