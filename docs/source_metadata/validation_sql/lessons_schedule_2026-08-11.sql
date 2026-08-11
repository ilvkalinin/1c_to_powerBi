-- SV-073: «Уроки и расписание» — read-only source controls.
-- Run in BEGIN TRANSACTION READ ONLY, statement_timeout = 30000.

-- LS-V01: technical document IDs, state flags and interval quality.
WITH lessons AS (
  SELECT 'GZ' AS source_kind, _idrref, _fld3218 AS lesson_start_at, _fld3219 AS lesson_end_at, _posted, _marked
  FROM public._document279 WHERE _fld3218 >= DATE '2024-01-01' AND _fld3218 < DATE '2027-01-01'
  UNION ALL
  SELECT 'PZ', _idrref, _fld4306, _fld4307, _posted, _marked
  FROM public._document329 WHERE _fld4306 >= DATE '2024-01-01' AND _fld4306 < DATE '2027-01-01'
)
SELECT source_kind, count(*) AS rows, count(DISTINCT _idrref) AS ids,
       count(*) FILTER (WHERE lesson_end_at <= lesson_start_at) AS nonpositive_intervals,
       count(*) FILTER (WHERE mod(extract(epoch FROM lesson_end_at - lesson_start_at)::bigint, 300) <> 0) AS nonmultiple_5m,
       count(*) FILTER (WHERE NOT _posted) AS unposted, count(*) FILTER (WHERE _marked) AS marked
FROM lessons GROUP BY 1;

-- LS-V02: exact current-M PZ GUID plus cancellation document observation.
SELECT d._posted, d._marked,
       d._fld4323rref = decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS current_status,
       EXISTS (SELECT 1 FROM public._document313 c WHERE c._fld3810_rrref = d._idrref) AS has_cancellation,
       count(*) AS rows
FROM public._document329 d
WHERE d._fld4306 >= DATE '2024-01-01' AND d._fld4306 < DATE '2027-01-01'
GROUP BY 1, 2, 3, 4;

-- LS-V03: valid July-2026 intervals have exactly one slot per five minutes.
WITH lessons AS (
  SELECT 'GZ' AS source_kind, _idrref, _fld3218 AS lesson_start_at, _fld3219 AS lesson_end_at FROM public._document279
  WHERE _fld3218 >= DATE '2026-07-01' AND _fld3218 < DATE '2026-08-01'
  UNION ALL SELECT 'PZ', _idrref, _fld4306, _fld4307 FROM public._document329
  WHERE _fld4306 >= DATE '2026-07-01' AND _fld4306 < DATE '2026-08-01'
), valid AS (
  SELECT *, extract(epoch FROM lesson_end_at - lesson_start_at)::bigint / 300 AS expected_slots
  FROM lessons WHERE lesson_end_at > lesson_start_at
    AND mod(extract(epoch FROM lesson_end_at - lesson_start_at)::bigint, 300) = 0
), slots AS (
  SELECT v.*, generate_series(lesson_start_at, lesson_end_at - interval '5 minutes', interval '5 minutes') AS slot_start_at FROM valid v
)
SELECT (SELECT count(*) FROM valid) AS valid_lessons, (SELECT sum(expected_slots) FROM valid) AS expected_slots,
       count(*) AS actual_slots, count(*) FILTER (WHERE slot_start_at < lesson_start_at OR slot_start_at >= lesson_end_at) AS outside_slots
FROM slots;

-- LS-V04—LS-V06: dimension orphan / payment-class / legacy lateness controls.
-- The executed version measures both branches separately; see SV-073 for results.
