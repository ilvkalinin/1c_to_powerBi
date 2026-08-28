# Authorization: physical admission of mart.promo_application

User approval: 2026-08-28, explicit «да» to the exact package below.
Report: promo_codes. Object: mart.promo_application.

## Immutable reviewed set

* mapping: docs/mappings/promo_codes.md and ADR-0018;
* data contract: docs/data_contracts/promo_codes.md;
* source extract: sql/marts/promo_application_source_extract.sql;
* DDL: sql/marts/promo_application_ddl.sql;
* runner: scripts/load_promo_application.py;
* target reconciliation: sql/tests/promo_application_reconciliation.sql;
* technical evidence: docs/reports/promo_application_stage3_technical_review_execution_2026-08-28.md.

## Authorized operations

One initial target DDL and source-first derived-column binary COPY to
mart.promo_application; separate independent source controls before each COPY;
short-lived target transaction under advisory lock; target-stage reconciliation,
target read plan, relation-size measurement and one atomic rerun. Source stays
read-only. No source DDL/DML/index, raw source replica, Power BI/M/DAX change,
or unapproved target object is permitted.

Rollback: any failed copy/control/plan before COMMIT rolls back the target
transaction and retains the previous target state; temporary derived COPY files
are scoped to the attempt. Full rebuild is the only refresh design.

Closure: independent expected controls and target reconciliation pass for the
initial load and rerun; target read plan and physical size are recorded; no
partial target snapshot remains; Power BI boundary remains unchanged.

## Admission stop — 2026-08-28

Before target DDL/COPY, an independent read-only control assembled the two
exact PBIT M source paths and applied BR-003 horizon. It returned 132808 rows
(35028 promo_gift, 97780 discount), discount sum 861947783.61 and price sum
2156425843.80000. The reviewed candidate extract returned 132801 rows
(35028/97773), 861840283.61 and 2156159943.92000. This is
VALIDATION_FAILED, not a tolerable live-source movement comparison: both paths
ran in the same fresh source control session. Target actions remain NOT
EXECUTED. Replacing the immutable extract with the exact PBIT path requires a
new explicit approval and a renewed technical review.
