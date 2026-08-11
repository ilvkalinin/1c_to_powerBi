-- SV-072: «Контроль предварительной записи» — read-only source validation.
-- Execute in BEGIN TRANSACTION READ ONLY with statement_timeout = 30000.
-- The report's legacy window is _period >= 2024-01-01; an exclusive upper
-- bound 2027-01-01 made the live control reproducible on 2026-08-11.

-- PC-V02: InfoRg7006 technical key and Active distribution.
SELECT count(*) AS rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS technical_keys,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS duplicate_keys,
       min(_period) AS min_period,
       max(_period) AS max_period,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows
FROM public._inforg7006
WHERE _period >= DATE '2024-01-01' AND _period < DATE '2027-01-01';

-- PC-V03, PC-V04, PC-V07: document branch, source states and Enum448.
SELECT CASE
           WHEN p._idrref IS NOT NULL AND g._idrref IS NOT NULL THEN 'both'
           WHEN p._idrref IS NOT NULL THEN 'Document329'
           WHEN g._idrref IS NOT NULL THEN 'Document279'
           ELSE 'orphan'
       END AS branch,
       count(*) AS rows
FROM public._inforg7006 s
LEFT JOIN public._document329 p ON p._idrref = s._fld7007_rrref
LEFT JOIN public._document279 g ON g._idrref = s._fld7007_rrref
WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
GROUP BY 1 ORDER BY 1;

SELECT branch, active, posted, marked, count(*) AS rows
FROM (
    SELECT 'Document329'::text AS branch, s._active AS active,
           p._posted AS posted, p._marked AS marked
    FROM public._inforg7006 s
    JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
    UNION ALL
    SELECT 'Document279', s._active, g._posted, g._marked
    FROM public._inforg7006 s
    JOIN public._document279 g ON g._idrref = s._fld7007_rrref
    WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
) q
GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;

SELECT coalesce(e._enumorder::text, 'orphan') AS enum_order, count(*) AS rows
FROM public._inforg7006 s
LEFT JOIN public._enum448 e ON e._idrref = s._fld7013rref
WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
GROUP BY 1 ORDER BY 1;

-- PC-V05: do not replace the service or club stored in InfoRg7006 by the
-- document field until their observed mismatches have an approved rule.
WITH state AS (
    SELECT s.*, CASE WHEN p._idrref IS NOT NULL THEN 'PZ' ELSE 'GZ' END AS branch,
           p._fld4310rref AS pz_club, p._fld4316rref AS pz_service,
           g._fld3224rref AS gz_club, g._fld3226rref AS gz_service,
           p._fld4322rref AS pz_employee, g._fld3223rref AS gz_employee
    FROM public._inforg7006 s
    LEFT JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    LEFT JOIN public._document279 g ON g._idrref = s._fld7007_rrref
    WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
)
SELECT branch, count(*) AS events,
       count(*) FILTER (WHERE c._idrref IS NULL) AS client_orphans,
       count(*) FILTER (WHERE club._idrref IS NULL) AS registry_club_orphans,
       count(*) FILTER (WHERE svc._idrref IS NULL) AS registry_service_orphans,
       count(*) FILTER (WHERE emp._idrref IS NULL) AS employee_orphans,
       count(*) FILTER (WHERE (branch = 'PZ' AND _fld7009rref <> pz_club)
                         OR (branch = 'GZ' AND _fld7009rref <> gz_club)) AS club_mismatches,
       count(*) FILTER (WHERE (branch = 'PZ' AND _fld7010rref <> pz_service)
                         OR (branch = 'GZ' AND _fld7010rref <> gz_service)) AS service_mismatches,
       count(*) FILTER (WHERE act._idrref IS NULL) AS activity_orphans
FROM state
LEFT JOIN public._reference141x1 c ON c._idrref = state._fld7008rref
LEFT JOIN public._reference132 club ON club._idrref = state._fld7009rref
LEFT JOIN public._reference163 svc ON svc._idrref = state._fld7010rref
LEFT JOIN public._reference225 emp ON emp._idrref = CASE WHEN branch = 'PZ' THEN pz_employee ELSE gz_employee END
LEFT JOIN public._reference70 act ON act._idrref = svc._fld1733rref
GROUP BY branch ORDER BY branch;

-- PC-V06: client-code observability; no personal values are selected.
SELECT count(*) AS clients,
       count(*) FILTER (WHERE _code IS NULL) AS null_codes,
       count(*) FILTER (WHERE _code = '') AS empty_codes,
       (SELECT count(*) FROM (
           SELECT _code FROM public._reference141x1
           WHERE _code IS NOT NULL GROUP BY _code HAVING count(*) > 1
       ) duplicate_codes) AS duplicate_non_null_code_groups
FROM public._reference141x1;

-- PC-V09: the observed legacy left join to booking service rows.
WITH pz AS (
    SELECT s._recordertref, s._recorderrref, s._lineno, p._idrref AS booking_id
    FROM public._inforg7006 s
    JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
), joined AS (
    SELECT pz.*, v._lineno4353, v._fld4358rref
    FROM pz
    LEFT JOIN public._document329_vt4352 v ON v._document329_idrref = pz.booking_id
), line_counts AS (
    SELECT booking_id, count(_lineno4353) AS service_rows
    FROM joined GROUP BY 1
)
SELECT (SELECT count(*) FROM pz) AS source_events,
       (SELECT count(*) FROM joined) AS legacy_join_rows,
       (SELECT count(*) FROM joined) - (SELECT count(*) FROM pz) AS join_excess,
       (SELECT count(*) FROM line_counts WHERE service_rows > 1) AS bookings_with_multiple_service_rows,
       (SELECT max(service_rows) FROM line_counts) AS max_service_rows_per_booking,
       count(*) FILTER (WHERE _fld4358rref = decode('a0f1524d502e0d5d4c1dfeb9d5bbb3fe', 'hex')) AS employee_settlement_join_rows
FROM joined;

-- PC-V10: current DAX plan count is COUNT(_fld6619).
WITH base AS (
    SELECT * FROM public._inforg6612
    WHERE _fld6613 >= DATE '2024-01-01' AND _fld6613 < DATE '2027-01-01'
), logical_dups AS (
    SELECT _fld6613, _fld6614rref, _fld6615rref, _fld6616rref, _fld6619, count(*) AS n
    FROM base GROUP BY 1, 2, 3, 4, 5 HAVING count(*) > 1
)
SELECT count(*) AS plan_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS technical_keys,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE _fld6619 IS NULL) AS null_planned_client_rows,
       count(*) FILTER (WHERE _fld6619 IS NOT NULL) AS legacy_count_fld6619,
       (SELECT count(*) FROM logical_dups) AS duplicate_logical_groups
FROM base;

-- PC-V11 and PC-V12: keep the two one-to-many joins separately aggregated.
SELECT count(*) AS lessons, count(DISTINCT _idrref) AS distinct_lesson_ids,
       count(*) FILTER (WHERE _fld3222 IS NULL) AS null_capacity,
       min(_fld3222) AS min_capacity, max(_fld3222) AS max_capacity,
       count(*) FILTER (WHERE NOT _posted) AS unposted_lessons,
       count(*) FILTER (WHERE _marked) AS marked_lessons,
       count(*) FILTER (WHERE _fld3228) AS prepaid_lessons,
       count(*) FILTER (WHERE NOT _fld3228) AS nonprepaid_lessons
FROM public._document279
WHERE _fld3218 >= DATE '2024-01-01' AND _fld3218 < DATE '2027-01-01';

WITH lessons AS (
    SELECT _idrref FROM public._document279
    WHERE _fld3218 >= DATE '2024-01-01' AND _fld3218 < DATE '2027-01-01'
), attendance_per_lesson AS (
    SELECT i._fld8676rref AS lesson_id, count(*) AS attendance_rows,
           min(i._fld8677) AS min_arrived, max(i._fld8677) AS max_arrived
    FROM public._inforg8675 i JOIN lessons l ON l._idrref = i._fld8676rref
    GROUP BY 1
)
SELECT count(*) AS lessons_with_attendance, sum(attendance_rows) AS attendance_rows,
       count(*) FILTER (WHERE attendance_rows > 1) AS lessons_with_multiple_attendance_rows,
       max(attendance_rows) AS max_attendance_rows_per_lesson,
       count(*) FILTER (WHERE min_arrived <> max_arrived) AS lessons_with_conflicting_arrived_count
FROM attendance_per_lesson;

WITH lessons AS (
    SELECT _idrref FROM public._document279
    WHERE _fld3218 >= DATE '2024-01-01' AND _fld3218 < DATE '2027-01-01'
), state_per_lesson AS (
    SELECT s._fld7007_rrref AS lesson_id, count(*) AS state_rows,
           count(*) FILTER (WHERE e._enumorder = 1) AS expected_rows,
           count(*) FILTER (WHERE e._enumorder IN (2, 3)) AS cancel_rows,
           count(*) FILTER (WHERE e._enumorder = 4) AS arrived_rows,
           count(*) FILTER (WHERE e._idrref IS NULL) AS orphan_enum_rows
    FROM public._inforg7006 s
    JOIN lessons l ON l._idrref = s._fld7007_rrref
    LEFT JOIN public._enum448 e ON e._idrref = s._fld7013rref
    GROUP BY 1
)
SELECT count(*) AS lessons_with_state, sum(state_rows) AS state_rows,
       sum(expected_rows) AS expected_rows, sum(cancel_rows) AS cancel_rows,
       sum(arrived_rows) AS arrived_rows, sum(orphan_enum_rows) AS orphan_enum_rows,
       max(state_rows) AS max_state_rows_per_lesson
FROM state_per_lesson;

-- PC-V08/PC-V13: source-side legacy time categories. This is not an
-- independent reconciliation with Power BI cards.
WITH events AS (
    SELECT s._period, e._enumorder,
           CASE WHEN p._idrref IS NOT NULL THEN p._fld4306 ELSE g._fld3218 END AS lesson_start,
           CASE WHEN p._idrref IS NOT NULL THEN p._fld4307 ELSE g._fld3219 END AS lesson_end
    FROM public._inforg7006 s
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    LEFT JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    LEFT JOIN public._document279 g ON g._idrref = s._fld7007_rrref
    WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
      AND e._enumorder IN (1, 2, 3)
), categorized AS (
    SELECT *, CASE
        WHEN lesson_start IS NULL OR lesson_end IS NULL OR lesson_end < lesson_start THEN 'invalid_lesson_interval'
        WHEN _enumorder = 1 AND _period < date_trunc('day', lesson_start) THEN 'expected_before_previous_day_cutoff'
        WHEN _enumorder = 1 AND _period < lesson_end THEN 'expected_before_lesson_end'
        WHEN _enumorder = 1 AND _period < date_trunc('day', lesson_end) + INTERVAL '1 day' THEN 'expected_after_lesson_end_same_day'
        WHEN _enumorder = 1 THEN 'expected_next_day_or_later'
        WHEN _enumorder IN (2, 3) AND _period < date_trunc('day', lesson_start) THEN 'cancel_before_previous_day_cutoff'
        WHEN _enumorder IN (2, 3) THEN 'cancel_after_previous_day_cutoff'
        ELSE 'unclassified'
    END AS category
    FROM events
)
SELECT category, count(*) AS rows FROM categorized GROUP BY 1 ORDER BY 1;

WITH events AS (
    SELECT (CASE WHEN p._idrref IS NOT NULL THEN p._fld4306 ELSE g._fld3218 END)::date AS lesson_date
    FROM public._inforg7006 s
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    LEFT JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    LEFT JOIN public._document279 g ON g._idrref = s._fld7007_rrref
    WHERE s._period >= DATE '2024-01-01' AND s._period < DATE '2027-01-01'
      AND e._enumorder IN (1, 2, 3)
)
SELECT min(lesson_date) AS min_lesson_date, max(lesson_date) AS max_lesson_date,
       count(DISTINCT lesson_date) AS populated_days, count(*) AS qualified_events
FROM events;
