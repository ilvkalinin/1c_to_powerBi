# Stage 2 validation: `mart.employee_activity_interval`

- Package: `employee_activity_interval_stage2_validation_2026-08-27`
- Scope: `employee_workload`, read-only source validation only
- Source transaction: fresh `REPEATABLE READ, READ ONLY` session per control
- Horizon: BR-003 `[2025-01-01, 2026-08-28)`; the rolling-month overlap
  control uses the exact current-M window.
- No target connection, DDL, DML, `COPY`, Power BI change, or source mutation
  occurred.

## Current Power BI evidence

The local `Pbit_old/Загрузка сотрудников.pbit` was inspected from its
`DataModelSchema`.  The current model has an active relationship from
`Купоны[visit_date]` to `_Спр Дата[Date]`, as well as relationships on coupon
period, registration date, contract dates, class bounds, trainer, club and
activity. Follow-up validation proved that the calendar date is invariant in
every repeated current-M coupon group; only the unexposed visit timestamp
varies.

## Control results

| Control | Expected result | Actual result | Status |
|---|---|---|---|
| EW-V01 | unique `InfoRg7006` technical key; no ambiguous PZ/GZ branch | 2,882,792 rows; 0 duplicate technical keys; 0 ambiguous branches; 2,361,998 rows outside PZ/GZ branches; 14,578 observed `VT4352` excess rows | PASS — unsupported recorder rows stay outside this mart |
| EW-V02 | observable state fields; preserve M state filter | 2,868,215 rows; all active; 75 missing enum; 553,062 with current `Enum448` order 4; no unposted/marked scoped PZ/GZ rows | PASS |
| EW-V02A | exact current-M lesson eligibility and VT technical uniqueness | 444,784 PZ rows; 389,006 eligible PZ; 53,197 PZ excluded by cancellation after status/posting; 0 nonpositive eligible PZ; 7,431 PZ VT join excess; 0 duplicate `(PZ, VT line)` keys; 388,539 GZ rows, 348,538 eligible, 3 nonpositive | PASS with 3 invalid GZ rows excluded by interval guard |
| EW-V03 / EW-V03C | valid duties; no M-grain collision | 45,630 duty rows; 0 duplicate current-M input rows; 0 nonpositive intervals; 0 stored-minute mismatches; 45,630 current-M groups and 0 ID/name collisions | PASS |
| EW-V03A | union and raw coupon overlap coincide if clean duty is safely additive | 4,579 duties; 429 with coupon overlap; 49 with double-subtraction risk; 4 negative current-M clean duties; union variant has 0 negatives; 3,442 duplicate overlap minutes | PASS as legacy evidence — BR-018 preserves raw current-M result; union is not applied |
| EW-V03B | coupon `Table.Distinct` has a deterministic physical equivalent | 44,570 ranked rows; 44,370 latest PZ/service rows; 13,584 rows before current-M distinct; 13,428 after; 311 participating in collapsed keys; 149 collapsed keys have divergent retained payload; 0 null/nonpositive coupon-minute rows | PASS after follow-up: only visit timestamp differs |
| EW-V04 | active plan technical keys unique | 525,289 rows, all active, 0 duplicate keys, active amount 717,831,825.41 | PASS / reuse evidence |
| EW-V05 | one SCUD client maps to at most one employee | 8,322,098 visits; 7,786,617 have no employee link; 1,292 have multiple links; maximum 697 | BLOCKED for separate `employee_presence_day`; does not assign an employee in this mart |
| EW-V06 | independent DPFU reuse controls available | `7575`: 512,795 rows, quantity 516,176.000, revenue 651,745,644.85; `7646`: 500 rows, quantity 494.000, revenue 28,095.00 | PASS / reuse evidence |
| EW-V07 | deterministic historical employment interval | 8,724 rows; 655 nonpositive intervals; 187 overlapping pairs | BLOCKED for historical employment attribution; not used to fabricate activity rows |

## Source-plan evidence

Exact EW-V03B one-month source sample (`2025-08-01` through
`2025-09-01`) ran as `EXPLAIN (ANALYZE, BUFFERS)`: 7,927.903 ms execution,
37.105 ms planning, 767,449 shared-hit and 26,304 shared-read blocks, no temp
files.  The initial full control was deliberately cancelled at its 180-second
source statement timeout and has no accepted result.  A single later full
read-only run with a 360-second limit completed in 177,103.035 ms; no
parallel transport or second heavy plan was run.

## Confirmed physical-key boundary

The lesson/duty branches can be keyed without inventing a source identifier:

- PZ lesson row: `PZ` + `Document329._IDRRef` + `VT4352._LineNo4353` (or a
  fixed no-VT marker); current multiplicity is preserved.
- GZ lesson row: `GZ` + `Document279._IDRRef`.
- Duty output row: a stable hash of the exact current-M grouping fields
  `(club_id, employee_id, room_id, start_at, end_at, duty_minutes)`.

Current M performs `Table.Distinct` on `client_code, club, division_name,
employee, service_name, class_start` while retaining `visit_date`. The follow-up
control showed that the 149 non-singleton groups differ only by visit timestamp;
their calendar day, coupon minutes, contract and IDs are identical. The
physical coupon key can therefore use the same group with encoded IDs and
`class_start`, while `activity_date = visit_at::date`.

## Stage-3 boundary

No Stage 3 SQL plan exists and no physical object may be created. The next
package may prepare an immutable reviewed Stage 3 plan only. The first release
preserves PZ/GZ state filters, VT multiplicity and raw coupon-duty subtraction,
then applies BR-040 to clamp the four observed negative clean duties to zero;
replacing raw subtraction by interval union remains a separate methodology
change.
