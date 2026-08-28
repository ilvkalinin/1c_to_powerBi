# Stage 3 product admission execution: `mart.fitness_funnel_client_start`

Status: `DECISION_REQUIRED`.  The physical admission package is active, but
target creation is not permitted until the approved cohort attribute rule is
changed or the full-horizon source result changes.

## Scope and safety boundary

Execution follows the approved
[admission authorization](fitness_funnel_client_start_stage3_product_admission_authorization_2026-08-28.md).
All source work used fresh `REPEATABLE READ, READ ONLY` sessions and the
project retry helper.  `work_mem = 64MB` was scoped with `SET LOCAL` to those
source sessions only.  No source object was changed.  `mart` was not
contacted: no target DDL, DML, COPY, reconciliation, read plan or rerun ran.

## Exact source-plan evidence

The reviewed extract was measured without concurrent transport for the full
legacy horizon `[2024-01-01, 2026-08-28)`.

| Window | Rows | Planning ms | Execution ms | Shared hit/read | Temp read/write | Result |
|---|---:|---:|---:|---|---|---|
| 1 month `[2026-07-01, 2026-08-28)` | 11,836 | 4.323 | 316.064 | 63,098 / 105 | 0 / 0 | PASS |
| 2 months `[2026-06-01, 2026-08-28)` | 18,139 | 4.038 | 394.380 | 97,587 / 67 | 0 / 0 | PASS |
| 3 months `[2026-05-01, 2026-08-28)` | 23,455 | 3.774 | 459.826 | 125,822 / 49 | 0 / 0 | PASS |
| 6 months `[2026-02-01, 2026-08-28)` | 46,492 | 3.736 | 877.524 | 247,149 / 214 | 0 / 0 | PASS |
| full, baseline | 231,536 | 4.324 | 4,653.565 | 614,368 / 12,857 | 3,527 / 3,528 | final sort spilled |
| full, `SET LOCAL work_mem = '64MB'` | 231,536 | 3.952 | 3,210.008 | 620,499 / 0 | 0 / 0 | PASS; no spill |

The exact full extract has stable row cardinality.  The only accepted tuning is
the measured session-local `work_mem = '64MB'`; it was added to the guarded
source export runner.  No index, planner-global setting or 1C object changed.

## Full-horizon independent source controls

The controls were run independently of the extract over
`[2024-01-01, 2026-08-28)` in a second fresh snapshot.

| Control | Observed result | Status |
|---|---|---|
| FF-S01 | 231,645 eligible contracts; duplicate refs 0; marked 1; client orphans 0; club orphans 0 | PASS for required shape gates; marked count is observed, not an exclusion rule |
| FF-S02 | 231,490 client-start cohorts; 153 multi-contract cohorts / 308 contracts / maximum 4 contracts; **32 multi-club** and **24 multi-tenure** cohorts | FAIL |
| FF-S03 | 231,536 target candidate rows; nulls 0; future starts 0; **46 duplicate `(client_key, membership_start_date)` keys** | FAIL |

The conflict is material to the approved client-start contract, not a loading
or performance fault.  There are 46 ambiguous client-date cohorts, including
10 with both kinds of conflict.  For example, one single client/date cohort
has two eligible contracts with two access clubs and the same `Renew` tenure;
another has two clubs and both `New` and `Renew`.  Retaining both source
combinations would violate the approved primary key; selecting either contract
would invent a principal-contract rule.

## Required decision

The prior approved rule says that multiple contracts on the same client/date
are one cohort and explicitly forbids silently selecting a principal contract.
Therefore the current immutable extract, DDL and runner cannot pass the
admission criterion.  A new approved business rule must choose one of these
directions before any target operation:

1. exclude the 46 ambiguous client-date cohorts from the client-start mart;
2. define an evidence-based deterministic contract/attribute selector;
3. extend the target grain to retain each distinct club/tenure combination;
4. retain one client-date row but remove `access_club_id` and `tenure_type`
   from this fact, with any attribute detail designed separately.

Each option changes the current target contract or client-count semantics and
requires a revised immutable SQL/reconciliation set and a new physical
admission package.  The existing target remains unchanged because it does not
exist.

## Subsequent business direction: later purchase date

The user chose the contract with the later purchase date on 2026-08-28.
Read-only source metadata confirms that `Reference59.Fld674` is a non-null
`timestamp without time zone`; none of the 231,645 eligible contracts has a
null or `0001-01-01` sentinel.  Ordering ambiguous client-date candidates by
`Fld674 DESC` resolves 40 of the 46 ambiguous cohorts.

The user subsequently chose the larger `Reference59.Fld693` contract term as
the second rank when maximum purchase timestamps are equal.  For example,
client `И00065989` has two contracts purchased 2024-07-31 for the same
2024-08-07 start: `Fld693` values 365 and 30 (actual intervals 364 and 29
calendar days), so the longer contract wins.  No SQL, DDL, DML or target
operation was changed after this finding.  Before a revised immutable set, a
full-horizon source control must prove whether any contracts remain tied on
both purchase date and term.
