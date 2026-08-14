-- S3-PB-001 — read-only current-rule controls for mart.prebooking_state_event.
-- Execute in REPEATABLE READ, READ ONLY. BR-003 bounds apply to lesson start.

WITH calendar_bounds AS (
    SELECT CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 1 AND 3
                THEN (date_trunc('year', CURRENT_DATE) - INTERVAL '2 years')::date
                ELSE (date_trunc('year', CURRENT_DATE) - INTERVAL '1 year')::date
           END AS date_from,
           (date_trunc('year', CURRENT_DATE) + INTERVAL '1 year')::date AS date_to
), pz AS (
    SELECT s._recordertref, s._recorderrref, s._lineno, v._lineno4353,
           e._enumorder, s._period AS state_event_at, p._fld4306 AS lesson_start_at
    FROM public._inforg7006 s
    JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    JOIN public._reference141x1 c ON c._idrref = s._fld7008rref
    JOIN public._reference132 club ON club._idrref = s._fld7009rref
    JOIN public._reference225 employee ON employee._idrref = p._fld4322rref
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    LEFT JOIN public._document329_vt4352 v ON v._document329_idrref = p._idrref
    LEFT JOIN public._reference163 document_service ON document_service._idrref = p._fld4316rref
    CROSS JOIN calendar_bounds b
    WHERE p._fld4306 >= b.date_from AND p._fld4306 < b.date_to
      AND s._fld7010rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea
      AND v._fld4358rref <> '\\xa0f1524d502e0d5d4c1dfeb9d5bbb3fe'::bytea
      AND e._enumorder IN (1, 2, 3)
      AND document_service._parentidrref IS DISTINCT FROM '\\x4296a4bf013441d111e7cae05001072c'::bytea
), gz AS (
    SELECT s._recordertref, s._recorderrref, s._lineno,
           NULL::numeric(5,0) AS _lineno4353, e._enumorder,
           s._period AS state_event_at, g._fld3218 AS lesson_start_at
    FROM public._inforg7006 s
    JOIN public._document279 g ON g._idrref = s._fld7007_rrref
    JOIN public._reference141x1 c ON c._idrref = s._fld7008rref
    JOIN public._reference132 club ON club._idrref = s._fld7009rref
    JOIN public._reference225 employee ON employee._idrref = g._fld3223rref
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    CROSS JOIN calendar_bounds b
    WHERE g._fld3218 >= b.date_from AND g._fld3218 < b.date_to
      AND s._fld7010rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea
      AND e._enumorder IN (1, 2, 3, 4)
), target_rows AS (
    SELECT 'PZ'::text AS booking_kind,
           _recordertref, _recorderrref, _lineno, _lineno4353, _enumorder,
           state_event_at, lesson_start_at
    FROM pz
    UNION ALL
    SELECT 'GZ'::text,
           _recordertref, _recorderrref, _lineno, _lineno4353, _enumorder,
           state_event_at, lesson_start_at
    FROM gz
)
SELECT booking_kind, _enumorder::integer AS state_order,
       count(*)::bigint AS target_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno))::bigint AS source_events,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS legacy_join_excess,
       min(lesson_start_at)::date AS min_lesson_date,
       max(lesson_start_at)::date AS max_lesson_date
FROM target_rows
GROUP BY 1, 2
ORDER BY 1, 2;
