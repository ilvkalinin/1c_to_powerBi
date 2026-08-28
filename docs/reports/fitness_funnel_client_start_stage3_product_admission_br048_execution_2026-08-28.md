# Physical admission execution BR-048: `mart.fitness_funnel_client_start`

Status: `IMPLEMENTED / VALIDATED`.

The exact BR-048 extract was measured read-only for `[2024-01-01,2026-08-28)`:
231,490 rows, 2,369.051 ms, no temp spill. Derived binary COPY measured
22,144,258 bytes; the 28,000,000-byte cap was used. Two independent guarded
atomic runs completed successfully; each performed FF-S01—FF-S03, temporary
binary COPY, DDL when absent, `DELETE + INSERT`, and FF-R01—FF-R07 before
commit. Any failure would have rolled back the transaction.

Final target control: 231,490 rows; duplicate logical keys 0; contract
violations 0; start horizon `2024-01-01` through `2026-08-27`. Target read
plan for August returned 5,976 rows in 87.395 ms, shared hit/read 6,346/0.
Power BI and source 1C were unchanged. This is a measured full-rebuild
baseline, not an incremental SLA.
