# Stage 3 technical SQL review: `mart.fitness_funnel_client_start`

Status: `VALIDATED` for local technical design; physical delivery remains
`NOT APPROVED`. Package:
`fitness_funnel_client_start_stage3_technical_review_2026-08-28`.

## Scope and immutable reviewed set

This package implements only the technical-review scope authorized in
[authorization](fitness_funnel_client_start_stage3_technical_review_authorization_2026-08-28.md).
It does not create or change an object on VM-2.

- [mapping](../mappings/fitness_funnel.md), [data contract](../data_contracts/fitness_funnel.md)
  and [ADR-0026](../adr/0026-fitness-funnel-client-events.md);
- [source extract](../../sql/marts/fitness_funnel_client_start_source_extract.sql);
- [independent source controls](../../sql/marts/fitness_funnel_client_start_source_controls.sql);
- [future DDL](../../sql/marts/fitness_funnel_client_start_ddl.sql);
- [guarded future atomic runner](../../scripts/load_fitness_funnel_client_start.py);
- [target reconciliation](../../sql/tests/fitness_funnel_client_start_reconciliation.sql).

The target grain and primary key are `client_key × membership_start_date`.
`access_club_id` and `tenure_type` are retained only if every contract in a
client-start group has the same value.  The extract deliberately emits every
distinct attribute combination: it never chooses a principal contract.  Thus a
full-horizon conflict fails FF-S02 and the target primary key instead of
silently changing the cohort or its filters.

## PBIT evidence

The supplied `Фитнес воронка.pbit` was rechecked read-only on 2026-08-28.
Its SHA-256 is unchanged:
`9890f4a9c7734617557ebfb4aec1d8e4d9d8b801b9b8eb0e8c67a7171b64f20a`.
It contains nine business tables, 33 measures, 17 relationships (seven between
business sets) and no roles.  Legacy `НачалосьКонтрактов1` uses
`COUNT(Спр Абонементы[Ссылка])`; several legacy СПТ/detail measures use
contract links.  This is confirmed evidence of the current template, not a
replacement for the already approved client-start target rule.  No PBIT, M,
DAX, connection or relationship was changed.

## Source metadata and bounded control

Live source `gymdb` was queried in a fresh `REPEATABLE READ, READ ONLY`
session with the project retry helper.  `Reference59` fields used by the
extract are physical non-null `bytea` references and `timestamp without time
zone` dates; `Fld693` is `numeric(5,0)`. `Reference141X1.Fld1507` is nullable
`timestamp without time zone`. The primary-key indexes on all three sources
are present; the bounded start-date predicate uses existing
`_reference59_7 (_fld671, _idrref)`.

FF-S01—FF-S03 were executed independently from the extract on
`[2026-08-01, 2026-08-08)`:

| Control | Result | Status |
|---|---:|---|
| FF-S01 eligible rows / duplicate contract refs / marked / client or club orphans | 1,442 / 0 / 0 / 0 | PASS sample |
| FF-S02 eligible contracts / client-start cohorts / multi-contract cohorts | 1,442 / 1,442 / 0 | PASS sample |
| FF-S02 multi-club / multi-tenure cohorts | 0 / 0 | PASS sample |
| FF-S03 candidate rows / required nulls / future starts / duplicate target keys | 1,442 / 0 / 0 / 0 | PASS sample |

## Actual-plan evidence

The exact reviewed source extract, with no concurrent transport, was measured
on the same bounded window using `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`.
Planning was 4.291 ms; execution was 61.064 ms; output was 1,442 rows; shared
hit/read was 7,798/0 and temp read/write was 0/0. `_reference59_7` produced
1,510 candidates in 28.499 ms, followed by 1,510 primary-key client lookups;
the final aggregate and sort did not spill. No measured fact supports a source
index, changed join order or session-local planner setting.

This is a representative sample only. It is neither a full-range baseline nor
an incremental-refresh SLA.

## Future physical-admission requirements

Before any target connection, DDL, DML, COPY or full-range transport, a new
explicit physical-admission package must approve this immutable set and:

1. run FF-S01—FF-S03 on the full approved legacy horizon starting
   `2024-01-01`; `multi_club_cohorts`, `multi_tenure_cohorts`, orphan/null and
   duplicate-key controls must be zero;
2. measure the exact extract progressively on 1, 2, 3 and 6 months, then only
   measure a full range if the ladder has no timeout, nonlinear growth or
   material spill; record rows, time and I/O at each step;
3. set an evidence-based cap for the derived binary COPY file, execute source
   controls before COPY in each source snapshot, and use the guarded atomic
   runner only with the separately approved admission token;
4. execute FF-R01—FF-R07 in the target transaction, collect target read-plan
   evidence and perform an atomic rerun against its own fresh source controls.

The approved refresh mode is a bounded full rebuild only. There is no confirmed
watermark, late-change/deletion handling or one-minute incremental SLA.

## Operations not executed

`NOT_EXECUTED`: VM-2 connection; DDL; DML; COPY; transport; full-range plan;
target reconciliation; target read plan; atomic rerun; Power BI switch or any
Power BI edit. No source object, local external Excel file or PBIT was changed.
