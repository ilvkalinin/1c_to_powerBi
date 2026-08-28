# Physical admission execution: mart.promo_application

Status: VALIDATED. Package:
promo_application_stage3_product_admission_2026-08-28.

Initial load and atomic rerun were performed on 2026-08-28. Source remained
read-only. Each run first executed an independent control composed from the
two exact current-PBIT M paths in the same REPEATABLE READ source snapshot as
the derived-column binary COPY. Target DDL, temporary stage, reconciliation and
replace were in one transaction under an advisory lock. No Power BI, M or DAX
was modified.

| Run | Rows | promo_gift / discount | Date min/max | Discount sum | Price sum |
|---|---:|---:|---|---:|---:|
| initial | 132814 | 35031 / 97783 | 2025-01-02 / 2026-08-28 | 861953283.61 | 2156435343.80000 |
| atomic rerun | 132814 | 35031 / 97783 | 2025-01-02 / 2026-08-28 | 861953283.61 | 2156435343.80000 |

PA-R01 through PA-R10 passed inside each target transaction with zero
tolerance. Final target has zero duplicate report_row_id values and zero
null/empty client_key values. Relation total size: 63 MB.

Target acceptance query grouped 2026-06-01 through 2026-07-01 by source_kind:
6.376 ms execution, planning 3.242 ms, two result rows, shared hit 661/read 0.
The source full-rebuild baseline remains 39.236 s from the technical review;
this admission does not establish incremental refresh SLA. Live source movement
between earlier snapshots was observed and is not a reconciliation failure.

Rollback evidence: the first source-COPY attempt failed before target
connection because of a local SQL-comment syntax error; no target DDL/DML was
executed. The corrected initial run and rerun both committed atomically.
