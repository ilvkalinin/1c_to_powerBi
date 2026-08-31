# Incremental design: `crm_br032`

Статус: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The composite job has four physical facts. `crm_interaction` and
`club_day_metrics` have primary keys; `crm_interaction_phone` has its three
field key and must be replaced coherently with its parent. The feedback fact is
the confirmed final PBIT grouping and has no business key. A read-only target
control found 33 columns and zero duplicate complete canonical rows, so its
complete canonical row can be used for an exact multiset diff without adding a
target column or changing its grain.

The new runner will export one read-only source snapshot to isolated local
transport files, stage its four current facts in the target transaction, and
apply only source/target row differences to final targets. It deletes children
and old feedback rows before core, then inserts core before phone and the
remaining facts in one target transaction. A full diff is needed to detect late changes;
the measured composite full rerun is 827.380 seconds, so no one-minute SLA is
claimed. DML remains outside this design package.

## Target transaction order

1. Stage current source rows for all four facts before any delete.
2. Delete changed/absent `crm_interaction_phone` rows, then old full-row
   `feedback_interaction` rows, then changed/absent `crm_interaction` rows and
   changed `club_day_metrics` rows.
3. Insert current core rows before current phone rows, then feedback and
   club-day rows.
4. Recompute exact `EXCEPT ALL` source-stage/target multiset differences for
   all four facts before `COMMIT`; a mismatch rolls back the entire
   transaction.
