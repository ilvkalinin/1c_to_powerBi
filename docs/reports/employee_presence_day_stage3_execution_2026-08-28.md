# Execution: `mart.employee_presence_day` BR-045

Status: `VALIDATED / full-rebuild baseline only`.

Initial load and two atomic reruns were executed under the approved package.
Each runner invocation used an exported `REPEATABLE READ, READ ONLY` source
snapshot, independent source controls, twenty monthly derived binary COPY files,
a short VM-2 transaction with advisory lock and temporary stage, `DELETE +
INSERT`, in-transaction reconciliation and cleanup. No source object, Power BI
or raw source replica was changed.

## Final target snapshot

Final read-only audit: 351,327 rows;
142,028,863.69892505000000610178 minutes; dates 2025-01-01…2026-08-28;
NULL/negative violations = 0; duplicate logical keys = 0. A later independent
source audit may differ because the live source changes between snapshots; each
load/rerun reconciled only to its own source snapshot.

## Performance and optimization

Exact source extract ladder: 1 month 16,472 rows / 366.816 ms; 2 months
34,548 / 591.453 ms; 3 months 54,996 / 832.090 ms; 6 months 110,883 /
1,618.944 ms. Full baseline was 351,326 rows / 5,675.412 ms with temp
read/write 2,378/7,803 blocks. The only tested candidate,
`SET LOCAL work_mem = '128MB'`, returned the same 351,326 rows in 5,487.214 ms
with zero temp blocks; it is scoped only to the source sessions of this runner.

The final target read plan scanned 351,327 rows in 73.321 ms with shared hit
9,797, shared read 0 and temp 0. Target size is 126 MB. No additional index is
justified by this evidence. Full rebuild remains a measured baseline; no
watermark, late-change/delete handling or incremental SLA is claimed.

## Acceptance

`EP45-R01` rows, `EP45-R02` minutes, `EP45-R03/04` horizon and `EP45-R05`
contract passed inside each target transaction. Initial load and reruns committed
atomically; no rollback incident occurred. Power BI remains unchanged by BR-036.
