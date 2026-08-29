# RM-ASOF-S2-001: Stage 2 execution — observation history

Дата: 2026-08-29. Scope closed: only isolated `REPEATABLE READ, READ ONLY`
sessions on VM-1/VM-2. No DDL, DML, `COPY`, schedule, Power BI change or new
object was executed.

## Evidence

- [authorization](renewal_management_as_of_snapshot_stage2_authorization_2026-08-29.md) recorded every expected result before execution.
- [target controls](../source_metadata/validation_sql/renewal_management_as_of_snapshot_stage2_target_2026-08-29.sql), [source controls](../source_metadata/validation_sql/renewal_management_as_of_snapshot_stage2_source_2026-08-29.sql), and [runner](../../scripts/run_renewal_management_as_of_snapshot_stage2_validation.py) are exact executable evidence. Each statement uses a separate read-only repeatable-read session; source timeout is 300 seconds and target timeout is 60 seconds.
- Aggregate JSON was produced at execution time without PII. The relevant live source controls completed around 14:56 Moscow time; values below are transcribed from that evidence.

| Control | Actual result | Status |
|---|---|---|
| ASOF-V01 | VM-2 current fact: 240,967 rows, 240,967 distinct non-null `expiring_contract_id`, 0 duplicates. | `VALIDATED` |
| ASOF-V02 | 240,967 comparison rows; `renewal_type`, both Renew flags and contract-end date have 0 nulls. | `VALIDATED` for current-upstream comparison key |
| ASOF-V03 | Exact live VM-1 cohort was 240,965 contracts while the last committed VM-2 mart is 240,967. This expected live-source drift proves observation must read only the parent mart after successful commit. Existing parent loader commits its atomic target transaction before returning success. | `VALIDATED DESIGN PREREQUISITE`; failed-parent ordering remains Stage 3 acceptance |
| ASOF-V04 | `to_regclass('mart.renewal_management_contract_observation') IS NULL` = true. | `CONFIRMED` absence; future selector/REMOVED test `VALIDATION_PENDING` until Stage 3 |
| ASOF-V05 | Current cohort has 151,573 clients. Rating period ties: 0 groups / 0 clients; tenure period ties: 0 / 0. Both source `Period` fields are timestamps. | `VALIDATED` deterministic effective-period order |
| ASOF-V06 | 1,483,951 eligible interactions; both timestamps are non-null. 45,719 rows have `created_at > started_at`; 2 have a future started time in the live snapshot. `Reference67.Fld820` and `Fld823` are timestamps; current task stage/reason fields are bytea references. | `CONFIRMED` current timestamps; `BLOCKER` only for retrospective task funnel/fail state |
| ASOF-V07 | 240,965 contracts; 1 activation sentinel (`0001-01-01`), 264 activations after start, 0 purchase-after-start, 0 invalid service intervals. `Reference59.Fld670/671/672/674` are timestamps. | `BLOCKER` for retrospective known-at next-contract/cohort semantics |

## Findings and boundary

`InfoRg6861`/`InfoRg5654` now have a deterministic effective-period sequence in
the measured cohort, so they can be stored as forward observed current values.
The current source does not provide a confirmed temporal audit feed for
`Reference106` task funnel/fail fields or `Reference59` contract creation,
backdating, corrections and deletion. Existing source metadata also records
that `_reference106._version` is current-row metadata, not a temporal window.
Therefore neither current records nor the new observation product may be
labelled as a reconstructed 2025 source snapshot.

The user explicitly accepts either interaction timestamp. BR-051 preserves the
current-M choice, `Reference67.Fld820` (started), so this is not a remaining
business decision. The paid-first next-contract tie rule is already BR-050.

## Outcome

Forward append-only observation after a successful parent refresh remains the
recommended architecture. It will preserve every future observed change to
next contract, latest interaction, rating, tenure and current funnel values,
including contracts that ended in 2025/early 2026. It cannot populate a
truthful state before its first baseline observation.

No Stage 3 implementation is opened by this report. A later Stage 3 package
must contain immutable observation DDL/loader, target transition/reconciliation
controls, failure-ordering proof, measured baseline and a separate retention /
scheduling decision. A retrospective product instead needs an authoritative
history source and a new approved methodology package.
