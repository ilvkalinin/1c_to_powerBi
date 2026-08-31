# RM-ASOF-OPS-001—005: authorization — operation chain

Дата: 2026-08-29. User confirmed the operation package for the already
implemented observation fact.

## Scope

1. Create one PII-free VM-2 run journal and its reviewed DDL/controls.
2. Create one local wrapper: parent refresh first, observation append only on
   parent success; an exception produces a non-zero exit and records no false
   observation success.
3. Run one normal wrapper invocation and a no-change rerun; record counts and
   journal state. Real `CHANGED`/`REMOVED` rows are observed only on a later
   live parent change; do not fabricate them by mutating the parent mart.
4. Prepare, but do not install, the Windows Task Scheduler command because the
   current workspace has no authority/access to that external Windows host.

## Operational guardrail adjustment — 2026-08-31

The controlled rerun returned `FAILED_PARENT` after 248 seconds.  Its parent
loader used a per-statement source timeout of 180 seconds, although the wrapper
allowed 360 seconds for the complete source-and-target chain.  To keep the
bounded run internally consistent, the reviewed source SQL is unchanged while
the source statement cap is set to 300 seconds and the wrapper's whole-parent
cap to 480 seconds.  This is an execution safeguard only: it does not add a
source, target object, column, index, transport mode, or business rule.

## Explicit exclusions

No VM-1 mutation/raw replication, no Power BI change, no history deletion or
retention purge, no target index, and no artificial update/delete of the parent
or observation fact to simulate a change.

## Closure

Reviewed exact DDL/wrapper/controls are recorded; initial journal load,
successful no-change chain and failure guard are proved; Windows scheduler
handoff is documented as an external installation action, not silently claimed
as completed.
