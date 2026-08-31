# Incremental design: `crm_br032`

Статус: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The composite job has four physical facts. `crm_interaction` and
`club_day_metrics` have primary keys; `crm_interaction_phone` has its three
field key and must be replaced coherently with its parent. The feedback fact is
the confirmed final PBIT grouping and has no business key. A read-only target
control found 33 columns and zero duplicate complete canonical rows, so an
internal hash of all 33 fields can identify old/new feedback rows for a
multiset diff without adding a target column or changing its grain.

The new runner will build source/target diffs from one read-only source
snapshot, stage current rows for changed identities only, delete children and
old feedback rows before core, then insert core before phone and the remaining
facts in one target transaction. A full diff is needed to detect late changes;
the measured composite full rerun is 827.380 seconds, so no one-minute SLA is
claimed. DML remains outside this design package.
