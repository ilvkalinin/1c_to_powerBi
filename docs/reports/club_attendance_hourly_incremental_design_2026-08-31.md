# Incremental design: `mart.club_attendance_hourly`

Статус: `INCREMENTAL_CANDIDATE / IMPLEMENTATION_NOT_EXECUTED`.

`AccumRg7575._period` is event time rather than a change feed. Corrections to
its linked `Document325`, client, club or contract can alter any historical
visit date, so the runner does not invent a bounded lookback. The separate
`load_club_attendance_hourly_incremental.py` compares a double deterministic
fingerprint of every current source date with target rows of the same date.
It does not invoke or modify `load_club_attendance_hourly.py`.

On a match it performs no target DML. On a difference it re-extracts and
atomically replaces only the continuous range from the first to the last
differing visit date. It performs source/stage/target count, visit and minutes
controls, stage grain/contract checks, then a full pre-commit fingerprint
comparison. Deletions are represented by a source/target date mismatch and
are removed by the same replacement transaction.

The exact full source baseline is 413.220 s; a control month with
`enable_hashjoin = off` was 3.807 s. Thus this is a correctness-preserving
incremental target strategy, not a one-minute SLA. No DML, COPY or scheduler
task was executed in this design package.
