# Follow-up Stage 2 result: coupon visits and nonnegative duties

- Package: `employee_activity_interval_followup_stage2_2026-08-27`
- Boundary: source `REPEATABLE READ, READ ONLY` and local documentation only.
- No target connection, DDL, DML, `COPY`, Power BI change or source mutation
  occurred.

## What the coupon-visit join does

For a current coupon PZ row, M joins every `Document325` visit having the
same client, club and `InfoRg7006` calendar day, provided that its start time
is not later than the lesson start/end.  It does not select one visit.  M then
uses `Table.Distinct(client_code, club, division_name, employee, service_name,
class_start)`.

The earlier EW-V03B evidence found 311 input rows in non-singleton distinct
groups and 149 groups with different payload.  The follow-up exact full-horizon
source control proves the actual impact:

| Metric | Result |
|---|---:|
| Current-M coupon rows before / after `Table.Distinct` | 13,584 / 13,428 |
| Keys with different visit timestamp | 149 |
| Keys with different visit calendar day | 0 |
| Keys with different `quantity × service_time` | 0 |
| Keys with different contract bounds | 0 |
| Keys with different client/club/employee/service IDs | 0 |
| Null or nonpositive coupon minutes | 0 |

Each refinement used a fresh source `REPEATABLE READ, READ ONLY` transaction
over the same BR-003 horizon. The full minute/timestamp run completed in
224,578.726 ms; the calendar-day run in 156,042.612 ms; and the dimension-ID
run in 156,097.814 ms. No transport ran concurrently.

Thus repeated visit records are an intermediate join multiplicity only. They
do not change coupon count, duration, current calendar day, contract or
dimension selection. The target can reproduce current result deterministically
by grouping on the exact `Table.Distinct` business key and using
`visit_at::date` as `activity_date`; that date is group-invariant. It does not
store a visit timestamp.

## User decision: clean duty

The user explicitly set the rule that a negative clean-duty result is
impossible. `BR-040` therefore defines:

```text
clean_duty_minutes = GREATEST(0, duty_minutes - raw_coupon_overlap_minutes)
```

The raw qualifying coupon-overlap formula, coupon qualification and its
multiplicity remain unchanged. EW-V03A found four legacy negative results in
the rolling-month sample; they will become zero under BR-040. Interval-union
normalisation remains out of scope.

## Stage-3 boundary

The event key is now confirmed for every branch:

- PZ: `PZ + Document329 ID + VT4352 line/no-VT marker`;
- GZ: `GZ + Document279 ID`;
- duty: hash of `(club_id, employee_id, room_id, start_at, end_at,
  duty_minutes)`;
- coupon: hash of current-M distinct group `(client_code, club_id,
  activity_id, employee_id, service_id, class_start)`.

The next independent package may prepare an immutable Stage 3 SQL plan only;
physical DDL/DML/COPY still need its own explicit approval.
