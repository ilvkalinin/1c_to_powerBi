# Technical SQL review: `mart.employee_activity_interval`

Status: `REVIEWED / READY FOR PHYSICAL ADMISSION`.

The reviewed object is one isolated fact with the approved event grain and
key. `TRAINING` retains PZ/GZ lesson rows (including the current M VT4352
multiplicity); `DUTY` is one exact M duty group with BR-040
`GREATEST(0, raw-duty − raw-coupon-overlap)`; `COUPON_1/2` retains the
current coupon `Table.Distinct` group. Power BI remains unchanged.

## Immutable reviewed set

- [mapping](../mappings/employee_workload.md) and [contract](../data_contracts/employee_workload.md);
- [source extract](../../sql/marts/employee_activity_interval_extract.sql);
- [independent source controls](../../sql/marts/employee_activity_interval_source_controls.sql);
- [DDL](../../sql/marts/employee_activity_interval_ddl.sql);
- [atomic runner](../../scripts/load_employee_activity_interval.py);
- [target reconciliation](../../sql/tests/employee_activity_interval_reconciliation.sql).

The initial path creates `mart.employee_activity_interval`, fills only a
temporary target stage and commits DDL plus load in one transaction under an
advisory lock. Rerun uses the same lock and `DELETE + INSERT` in one
transaction, so failure preserves the prior table. A single binary temporary
file holds the bounded BR-003 output; no raw 1C replica or persistent target
stage is created. No index is proposed before the post-load read plan.

## Representative exact-extract evidence

Fresh source `REPEATABLE READ, READ ONLY`, `[2025-08-01, 2025-09-01)`:

| Metric | Result |
|---|---:|
| rows / distinct keys / contract violations | 31,128 / 31,128 / 0 |
| training / duty / coupon rows | 28,610 / 2,010 / 508 |
| BR-040 zero clean duties | 1,733 |
| planning / execution | 65.987 / 8,169.038 ms |
| shared hit / read / temp written | 1,248,356 / 0 / 0 |

Independent source controls on the same representative scope returned PZ/GZ
14,293/14,317 rows and 696,554/571,882 minutes; duties 2,010 rows and
81,099 clean minutes; coupons 508 rows and 16,300 minutes. Coupon output
minutes, visit day and dimension IDs had zero divergence. No target
connection, DDL, DML or COPY occurred in this review.

## Physical-admission criterion

Before execution, use a fresh source snapshot to obtain the independent
controls, then run the reviewed initial load and atomic rerun. Acceptance
requires zero source/stage/target deviations, contract/key/horizon checks,
the target read plan and measured full-rebuild timings. This is a full rebuild
baseline, never an incremental SLA.
