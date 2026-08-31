# RM-ASOF-OPS-001—005: execution record

Статус: `CLOSED`.

## Completed local and VM-2 actions

- Created `mart.renewal_management_observation_run` in one target transaction.
  It has no PII: only lifecycle timestamps, status, exit codes and counts of
  `BASELINE`/`CHANGED`/`REMOVED`; `OPS-R01` and the PUBLIC-access check passed.
- Added `run_renewal_management_observation_chain.py`. Its normal path is
  strictly `load_renewal_management_contract.py --rebuild` → successful
  `TARGET_COMMIT_PASS` marker → `load_renewal_management_contract_observation.py
  --append`. A non-zero parent outcome or a missing marker cannot invoke the
  observation loader. Parent timeout is bounded (default 360 seconds).
- Confirmed the failure guard without changing source/parent data: journal run
  `1` has `FAILED_PARENT`, parent code `1`, no observation exit code and zero
  inserted counts. Before the later connection loss, the same evidence also
  showed observation cardinality unchanged at 240,967 rows.
- Prepared an uninstalled [Windows Task Scheduler handoff](../operations/renewal_management_observation_windows_task_scheduler.md).
  No external Windows task was created because this workspace has no authority
  or connection to that host.

## Failed normal-chain attempt and recovery

The first normal chain reached the existing parent loader but did not reach the
observation append. Its VM-1 backend was proven to be this workflow's own
`idle in transaction / ClientRead` session for more than five minutes, with no
active statement. Only that stale backend was terminated; its transaction was
rolled back. The local child did not process the disconnect, so only that exact
own child process was stopped. Journal run `2` recorded `FAILED_PARENT`, exit
code `-15`, zero inserted counts and no observation invocation. No partial
parent or observation target state was accepted.

## Restored connectivity and executed controls — 2026-08-31

The execution environment again reached both VM-1 and VM-2 with `SELECT 1`.
There were no own running loader processes or stale source sessions before the
next execution.

- Journal run `3` is now independently confirmed as `SUCCEEDED`: parent and
  observation exit codes are both `0`; it recorded `BASELINE=1`,
  `CHANGED=843`, `REMOVED=4`.
- The first resumed full chain, run `4`, was `FAILED_PARENT` after 248 seconds
  and correctly did not invoke observation.  The parent loader's source
  statement cap (`180s`) was smaller than the measured end-to-end source phase
  while the wrapper allowed `360s` for the whole chain.  The reviewed SQL and
  objects were unchanged; the bounded source statement cap was aligned to
  `300s` and the whole-parent cap to `480s`.
- Full chain run `5` then succeeded (`0/0`) with independently reconciled live
  changes: `BASELINE=1`, `CHANGED=6904`, `REMOVED=16`.  Its parent snapshot had
  240,949 rows, and the observation fact had 248,736 rows immediately after
  commit.
- Full chain run `6` also succeeded (`0/0`) and found a further 13 real
  `CHANGED` rows.  No source or parent data was fabricated.
- A direct subsequent approved observation append, performed without changing
  the parent mart, committed zero rows and passed RMO-R01—RMO-R05.  This is the
  exact idempotence control for the observation append.

Final read-only controls at `2026-08-31T09:35+03:00` were all zero-deviation:

| Control | Expected | Actual | Result |
| --- | ---: | ---: | --- |
| RMO-R01 latest live states | 240,949 rows / contracts | 240,949 / 240,949 | PASS |
| RMO-R02 key/hash/required fields | 0 / 0 / 0 | 0 / 0 / 0 | PASS |
| RMO-R03 kind/date/future checks | 0 / 0 / 0 | 0 / 0 / 0 | PASS |
| RMO-R04 latest projection and tombstones | 0 / 0 / 0 | 0 / 0 / 0 | PASS |
| RMO-R05 horizon and PUBLIC access | 0 / 0 | 0 / 0 | PASS |
| OPS-R01 journal lifecycle/count/access | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 | PASS |

Final observation cardinality is 248,749 rows; the live parent mart has
240,949 rows.  The two equivalent as-of calculations both return 240,949
current rows.  Their measured target plans are `DISTINCT ON` 4,140.104 ms
(2,009/2,014 temp blocks) and grouped `MAX(observed_at)` plus join 618.274 ms
(6,241/6,241 temp blocks).  No index is created because it is outside this
package.

## Closure decision — 2026-08-31

The user confirmed that no further full rebuild is needed merely to seek a
zero-delta window after all data had already loaded.  The zero-row direct append
is accepted as the idempotence control: it exercises the reviewed historical
write path against an unchanged parent and passed every RMO control in its
atomic transaction.  The successful live-snapshot chains separately prove
correct capture of real `CHANGED` and `REMOVED` events; their per-run
reconciliation uses each run's own parent snapshot.

This closes RM-ASOF-OPS-001—005.  The prepared Windows Task Scheduler handoff
remains intentionally uninstalled, and no synthetic parent mutation, Power BI
change, raw replication, retention deletion or index was performed.
