-- SV-LS-001: mart.lesson_room_slot_5m — Stage 2 read-only source controls.
-- Run each statement in a repeatable-read, read-only transaction.
-- BR-003 horizon on 2026-08-14: [2025-01-01, 2027-01-01).
-- No query uses SELECT * or reads columns outside the candidate mart contract.

-- LS5-V01. Expected: the exact physical fields for the two document branches
-- and the duty register exist with stable types; document IDs are technically unique.
SELECT c.table_name, c.column_name, c.data_type, c.is_nullable
FROM information_schema.columns AS c
WHERE c.table_schema = 'public'
  AND (c.table_name, c.column_name) IN (
    ('_document279', '_idrref'), ('_document279', '_date_time'),
    ('_document279', '_posted'), ('_document279', '_marked'),
    ('_document279', '_fld3218'), ('_document279', '_fld3219'),
    ('_document279', '_fld3223rref'), ('_document279', '_fld3224rref'),
    ('_document279', '_fld3226rref'), ('_document279', '_fld3227rref'),
    ('_document329', '_idrref'), ('_document329', '_date_time'),
    ('_document329', '_posted'), ('_document329', '_marked'),
    ('_document329', '_fld4306'), ('_document329', '_fld4307'),
    ('_document329', '_fld4310rref'), ('_document329', '_fld4316rref'),
    ('_document329', '_fld4320rref'), ('_document329', '_fld4322rref'),
    ('_document329', '_fld4321rref'), ('_document329', '_fld4323rref'),
    ('_inforg7107', '_fld7108rref'), ('_inforg7107', '_fld7109rref'),
    ('_inforg7107', '_fld7110'), ('_inforg7107', '_fld7111'),
    ('_inforg7107', '_fld7112rref'), ('_inforg7107', '_fld7113rref'),
    ('_inforg7107', '_fld7115')
  )
ORDER BY c.table_name, c.column_name;

-- LS5-V02. Expected: each document produces at most one source lesson before
-- expansion and the current-rule qualifications remain explicit.  Group branch
-- reuses the confirmed mart.group_lesson qualification; PZ uses posted/current
-- status/no cancellation document, as approved in the mapping.  The output
-- separately exposes invalid and non-five-minute intervals; it does not round
-- or silently discard them.
WITH constants AS (
  SELECT DATE '2025-01-01' AS from_at, DATE '2027-01-01' AS to_at,
         decode('00000000000000000000000000000000', 'hex') AS empty_ref,
         decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS current_pz_status
), qualified AS (
  SELECT 'group_lesson'::text AS source_kind,
         d._idrref AS source_lesson_id,
         d._date_time AS created_at,
         d._fld3218 AS lesson_start_at,
         d._fld3219 AS lesson_end_at,
         d._fld3224rref AS club_id,
         d._fld3227rref AS room_id,
         d._fld3223rref AS employee_id,
         d._fld3226rref AS service_id
  FROM public._document279 AS d
  CROSS JOIN constants AS k
  WHERE d._fld3218 >= k.from_at AND d._fld3218 < k.to_at
    AND NOT d._marked
    AND d._fld3226rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
    AND EXISTS (SELECT 1 FROM public._reference225 AS employee WHERE employee._idrref = d._fld3223rref)
  UNION ALL
  SELECT 'prebooking'::text,
         d._idrref, d._date_time, d._fld4306, d._fld4307,
         d._fld4310rref, d._fld4320rref, d._fld4322rref, d._fld4316rref
  FROM public._document329 AS d
  CROSS JOIN constants AS k
  WHERE d._fld4306 >= k.from_at AND d._fld4306 < k.to_at
    AND d._posted
    AND d._fld4323rref = k.current_pz_status
    AND d._fld4321rref = k.empty_ref
    AND NOT EXISTS (
      SELECT 1 FROM public._document313 AS c
      WHERE c._fld3810_rrref = d._idrref
    )
)
SELECT source_kind,
       count(*) AS lessons,
       count(DISTINCT source_lesson_id) AS distinct_lesson_ids,
       count(*) - count(DISTINCT source_lesson_id) AS duplicate_lesson_ids,
       count(*) FILTER (WHERE lesson_start_at IS NULL OR lesson_end_at IS NULL) AS null_boundaries,
       count(*) FILTER (WHERE lesson_end_at <= lesson_start_at) AS nonpositive_intervals,
       count(*) FILTER (
         WHERE lesson_end_at > lesson_start_at
           AND mod(extract(epoch FROM lesson_end_at - lesson_start_at)::bigint, 300) <> 0
       ) AS nonmultiple_5m_intervals,
       count(*) FILTER (WHERE club_id IS NULL) AS null_club_ids,
       count(*) FILTER (WHERE room_id IS NULL) AS null_room_ids,
       count(*) FILTER (WHERE employee_id IS NULL) AS null_employee_ids,
       count(*) FILTER (WHERE service_id IS NULL) AS null_service_ids
FROM qualified
GROUP BY source_kind
ORDER BY source_kind;

-- LS5-V03. Expected: for every strictly positive interval divisible by five
-- minutes, [start, end) produces exactly duration/5 slots and none outside it.
-- The whole BR-003 horizon is controlled by the exact arithmetic total; the
-- actual expansion is deliberately limited to one current seven-day sample so
-- that a read-only validation does not materialize millions of derived slots.
WITH constants AS (
  SELECT DATE '2025-01-01' AS from_at, DATE '2027-01-01' AS to_at,
         decode('00000000000000000000000000000000', 'hex') AS empty_ref,
         decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS current_pz_status
), qualified AS (
  SELECT 'group_lesson'::text AS source_kind, d._idrref AS source_lesson_id,
         d._fld3218 AS lesson_start_at, d._fld3219 AS lesson_end_at
  FROM public._document279 AS d CROSS JOIN constants AS k
  WHERE d._fld3218 >= k.from_at AND d._fld3218 < k.to_at
    AND NOT d._marked
    AND d._fld3226rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
    AND EXISTS (SELECT 1 FROM public._reference225 AS employee WHERE employee._idrref = d._fld3223rref)
  UNION ALL
  SELECT 'prebooking'::text, d._idrref, d._fld4306, d._fld4307
  FROM public._document329 AS d CROSS JOIN constants AS k
  WHERE d._fld4306 >= k.from_at AND d._fld4306 < k.to_at
    AND d._posted AND d._fld4323rref = k.current_pz_status
    AND d._fld4321rref = k.empty_ref
    AND NOT EXISTS (SELECT 1 FROM public._document313 AS c WHERE c._fld3810_rrref = d._idrref)
), valid AS (
  SELECT *, extract(epoch FROM lesson_end_at - lesson_start_at)::bigint / 300 AS expected_slots
  FROM qualified
  WHERE lesson_end_at > lesson_start_at
    AND mod(extract(epoch FROM lesson_end_at - lesson_start_at)::bigint, 300) = 0
), all_horizon AS (
  SELECT source_kind, count(*) AS valid_lessons, coalesce(sum(expected_slots), 0) AS expected_slots
  FROM valid
  GROUP BY source_kind
), sample_valid AS (
  SELECT *
  FROM valid
  WHERE lesson_start_at >= TIMESTAMP '2026-08-01 00:00:00'
    AND lesson_start_at < TIMESTAMP '2026-08-08 00:00:00'
), sample_slots AS (
  SELECT v.source_kind, v.source_lesson_id, v.lesson_start_at, v.lesson_end_at,
         generate_series(v.lesson_start_at, v.lesson_end_at - interval '5 minutes', interval '5 minutes') AS slot_start_at
  FROM sample_valid AS v
)
SELECT a.source_kind, a.valid_lessons, a.expected_slots,
       count(s.slot_start_at) AS sample_actual_slots,
       coalesce((SELECT sum(v.expected_slots) FROM sample_valid AS v WHERE v.source_kind = a.source_kind), 0) AS sample_expected_slots,
       count(*) FILTER (WHERE s.slot_start_at < s.lesson_start_at OR s.slot_start_at >= s.lesson_end_at) AS sample_outside_slots,
       count(*) - count(DISTINCT (s.source_lesson_id, s.slot_start_at)) AS sample_duplicate_slot_keys
FROM all_horizon AS a
LEFT JOIN sample_slots AS s ON s.source_kind = a.source_kind
GROUP BY a.source_kind, a.valid_lessons, a.expected_slots
ORDER BY a.source_kind;

-- LS5-V04. Expected: service-to-activity/training-format and document-to-
-- dimension joins cannot multiply a qualified lesson.  Orphans stay observed
-- NULLs; no replacement by a description or a guessed ID is allowed.
WITH constants AS (
  SELECT DATE '2025-01-01' AS from_at, DATE '2027-01-01' AS to_at,
         decode('00000000000000000000000000000000', 'hex') AS empty_ref,
         decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS current_pz_status
), qualified AS (
  SELECT 'group_lesson'::text AS source_kind, d._idrref AS source_lesson_id,
         d._fld3224rref AS club_id, d._fld3227rref AS room_id, d._fld3223rref AS employee_id, d._fld3226rref AS service_id
  FROM public._document279 AS d CROSS JOIN constants AS k
  WHERE d._fld3218 >= k.from_at AND d._fld3218 < k.to_at AND NOT d._marked
    AND d._fld3226rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
    AND EXISTS (SELECT 1 FROM public._reference225 AS source_employee WHERE source_employee._idrref = d._fld3223rref)
  UNION ALL
  SELECT 'prebooking'::text, d._idrref, d._fld4310rref, d._fld4320rref, d._fld4322rref, d._fld4316rref
  FROM public._document329 AS d CROSS JOIN constants AS k
  WHERE d._fld4306 >= k.from_at AND d._fld4306 < k.to_at AND d._posted
    AND d._fld4323rref = k.current_pz_status AND d._fld4321rref = k.empty_ref
    AND NOT EXISTS (SELECT 1 FROM public._document313 AS c WHERE c._fld3810_rrref = d._idrref)
)
SELECT q.source_kind,
       count(*) AS qualified_lessons,
       count(*) FILTER (WHERE club._idrref IS NULL) AS club_orphans,
       count(*) FILTER (WHERE room._idrref IS NULL) AS room_orphans,
       count(*) FILTER (WHERE employee._idrref IS NULL) AS employee_orphans,
       count(*) FILTER (WHERE service._idrref IS NULL) AS service_orphans,
       count(*) FILTER (WHERE activity._idrref IS NULL) AS activity_orphans,
       count(*) FILTER (WHERE format._idrref IS NULL) AS training_format_orphans,
       count(*) - count(DISTINCT q.source_lesson_id) AS duplicate_lesson_ids_after_joins
FROM qualified AS q
LEFT JOIN public._reference132 AS club ON club._idrref = q.club_id
LEFT JOIN public._reference191 AS room ON room._idrref = q.room_id
LEFT JOIN public._reference225 AS employee ON employee._idrref = q.employee_id
LEFT JOIN public._reference163 AS service ON service._idrref = q.service_id
LEFT JOIN public._reference70 AS activity ON activity._idrref = service._fld1733rref
LEFT JOIN public._reference248 AS format ON format._idrref = service._fld1803rref
GROUP BY q.source_kind
ORDER BY q.source_kind;

-- LS5-V05. Expected: InfoRg7107 is a separate duty source, but the approved
-- room-slot contract has no duty branch because the current final lessons set
-- excludes its synthetic service "Дежурство".  Measure it only to preserve the
-- evidence and expose interval quality; do not add it to mart rows.
SELECT count(*) AS duty_rows,
       count(*) FILTER (WHERE _fld7110 IS NULL OR _fld7111 IS NULL) AS null_boundaries,
       count(*) FILTER (WHERE _fld7111 <= _fld7110) AS nonpositive_intervals,
       count(*) FILTER (
         WHERE _fld7111 > _fld7110
           AND mod(extract(epoch FROM _fld7111 - _fld7110)::bigint, 300) <> 0
       ) AS nonmultiple_5m_intervals,
       count(*) FILTER (WHERE _fld7108rref IS NULL) AS null_club_ids,
       count(*) FILTER (WHERE _fld7109rref IS NULL) AS null_employee_ids,
       count(*) FILTER (WHERE _fld7113rref IS NULL) AS null_room_ids
FROM public._inforg7107
WHERE _fld7110 >= DATE '2025-01-01' AND _fld7110 < DATE '2027-01-01'
  AND _fld7112rref = decode('bd57e817bb8afd31455f678cd21a2f8e', 'hex');

-- LS5-V06. Expected: branch-specific payment classes and the agreed lateness
-- expression remain observable without creating a universal document-state
-- rule.  PZ rows excluded by a cancellation document are represented as false;
-- GZ has no approved cancellation boolean and will remain NULL in the contract.
WITH constants AS (
  SELECT DATE '2025-01-01' AS from_at, DATE '2027-01-01' AS to_at,
         decode('00000000000000000000000000000000', 'hex') AS empty_ref,
         decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS current_pz_status
), qualified AS (
  SELECT 'group_lesson'::text AS source_kind, d._date_time AS created_at,
         d._fld3219 AS lesson_end_at, d._fld3226rref AS service_id
  FROM public._document279 AS d CROSS JOIN constants AS k
  WHERE d._fld3218 >= k.from_at AND d._fld3218 < k.to_at AND NOT d._marked
    AND d._fld3226rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
    AND EXISTS (SELECT 1 FROM public._reference225 AS employee WHERE employee._idrref = d._fld3223rref)
  UNION ALL
  SELECT 'prebooking'::text, d._date_time, d._fld4307, d._fld4316rref
  FROM public._document329 AS d CROSS JOIN constants AS k
  WHERE d._fld4306 >= k.from_at AND d._fld4306 < k.to_at AND d._posted
    AND d._fld4323rref = k.current_pz_status AND d._fld4321rref = k.empty_ref
    AND NOT EXISTS (SELECT 1 FROM public._document313 AS c WHERE c._fld3810_rrref = d._idrref)
), classified AS (
  SELECT q.source_kind,
         CASE
           WHEN q.source_kind = 'prebooking' AND service._idrref IS NULL THEN 'reserve'
           WHEN service._fld1778 IS TRUE THEN 'club_time'
           ELSE 'paid'
         END AS payment_class_current,
         (q.created_at > q.lesson_end_at) AS is_late
  FROM qualified AS q
  LEFT JOIN public._reference163 AS service ON service._idrref = q.service_id
)
SELECT source_kind, payment_class_current,
       count(*) AS lessons,
       count(*) FILTER (WHERE is_late) AS late_lessons,
       count(*) FILTER (WHERE NOT is_late) AS timely_lessons
FROM classified
GROUP BY source_kind, payment_class_current
ORDER BY source_kind, payment_class_current;
