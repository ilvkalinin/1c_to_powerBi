-- Source extract for mart.prebooking_state_event.
-- REVIEW ONLY. The runner binds $1/$2 to BR-003 bounds for lesson start and
-- opens one REPEATABLE READ, READ ONLY source snapshot. PZ multiplicity by
-- VT4352 is deliberate current-report behaviour.

WITH pz AS (
    SELECT s._period AS state_event_at,
           'PZ'::text AS booking_kind,
           encode(s._recordertref, 'hex') AS recorder_tref,
           encode(s._recorderrref, 'hex') AS recorder_id,
           s._lineno::integer AS source_line_no,
           v._lineno4353::integer AS legacy_settlement_line_no,
           encode(s._fld7007_rrref, 'hex') AS booking_document_id,
           p._fld4306 AS lesson_start_at, p._fld4307 AS lesson_end_at,
           encode(s._fld7009rref, 'hex') AS club_id,
           CASE WHEN activity._idrref IS NULL THEN NULL ELSE encode(document_service._fld1733rref, 'hex') END AS activity_id,
           encode(p._fld4322rref, 'hex') AS employee_id,
           encode(s._fld7010rref, 'hex') AS service_id,
           encode(s._fld7008rref, 'hex') AS client_key,
           CAST(client._code AS varchar(1000)) AS client_code,
           CAST(client._description AS varchar(1000)) AS client_name,
           e._enumorder::smallint AS state_order,
           CASE
             WHEN e._enumorder = 1 AND s._period < date_trunc('day', p._fld4306) THEN 'expected_before_previous_day_cutoff'
             WHEN e._enumorder = 1 AND s._period < p._fld4307 THEN 'expected_before_lesson_end'
             WHEN e._enumorder = 1 AND s._period < date_trunc('day', p._fld4307) + INTERVAL '1 day' THEN 'expected_after_lesson_end_same_day'
             WHEN e._enumorder = 1 THEN 'expected_next_day_or_later'
             WHEN e._enumorder IN (2, 3) AND s._period < date_trunc('day', p._fld4306) THEN 'cancel_before_previous_day_cutoff'
             ELSE 'cancel_after_previous_day_cutoff'
           END AS event_category,
           CASE WHEN e._enumorder = 1 THEN 1 ELSE -1 END::smallint AS booking_delta,
           CASE WHEN e._enumorder IN (2, 3) THEN s._period < p._fld4306 ELSE NULL END AS cancelled_before_lesson,
           true AS is_paid_booking
    FROM public._inforg7006 s
    JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    JOIN public._reference141x1 client ON client._idrref = s._fld7008rref
    JOIN public._reference132 club ON club._idrref = s._fld7009rref
    JOIN public._reference225 employee ON employee._idrref = p._fld4322rref
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    LEFT JOIN public._document329_vt4352 v ON v._document329_idrref = p._idrref
    LEFT JOIN public._reference163 document_service ON document_service._idrref = p._fld4316rref
    LEFT JOIN public._reference70 activity ON activity._idrref = document_service._fld1733rref
    WHERE p._fld4306 >= $1::date AND p._fld4306 < $2::date
      AND s._fld7010rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea
      AND v._fld4358rref <> '\\xa0f1524d502e0d5d4c1dfeb9d5bbb3fe'::bytea
      AND e._enumorder IN (1, 2, 3)
      AND document_service._parentidrref IS DISTINCT FROM '\\x4296a4bf013441d111e7cae05001072c'::bytea
), gz (
    state_event_at, booking_kind, recorder_tref, recorder_id, source_line_no,
    legacy_settlement_line_no, booking_document_id, lesson_start_at,
    lesson_end_at, club_id, activity_id, employee_id, service_id, client_key,
    client_code, client_name, state_order, event_category, booking_delta,
    cancelled_before_lesson, is_paid_booking
) AS (
    SELECT s._period, 'GZ'::text, encode(s._recordertref, 'hex'),
           encode(s._recorderrref, 'hex'), s._lineno::integer, NULL::integer,
           encode(s._fld7007_rrref, 'hex'), g._fld3218, g._fld3219,
           encode(s._fld7009rref, 'hex'),
           CASE WHEN activity._idrref IS NULL THEN NULL ELSE encode(document_service._fld1733rref, 'hex') END,
           encode(g._fld3223rref, 'hex'), encode(s._fld7010rref, 'hex'),
           encode(s._fld7008rref, 'hex'), CAST(client._code AS varchar(1000)),
           CAST(client._description AS varchar(1000)), e._enumorder::smallint,
           CASE
             WHEN e._enumorder = 1 AND s._period < date_trunc('day', g._fld3218) THEN 'expected_before_previous_day_cutoff'
             WHEN e._enumorder = 1 AND s._period < g._fld3219 THEN 'expected_before_lesson_end'
             WHEN e._enumorder = 1 AND s._period < date_trunc('day', g._fld3219) + INTERVAL '1 day' THEN 'expected_after_lesson_end_same_day'
             WHEN e._enumorder = 1 THEN 'expected_next_day_or_later'
             WHEN e._enumorder IN (2, 3) AND s._period < date_trunc('day', g._fld3218) THEN 'cancel_before_previous_day_cutoff'
             WHEN e._enumorder IN (2, 3) THEN 'cancel_after_previous_day_cutoff'
             ELSE 'arrived'
           END,
           CASE WHEN e._enumorder = 1 THEN 1 WHEN e._enumorder IN (2,3) THEN -1 ELSE 0 END::smallint,
           CASE WHEN e._enumorder IN (2,3) THEN s._period < g._fld3218 ELSE NULL END,
           g._fld3228
    FROM public._inforg7006 s
    JOIN public._document279 g ON g._idrref = s._fld7007_rrref
    JOIN public._reference141x1 client ON client._idrref = s._fld7008rref
    JOIN public._reference132 club ON club._idrref = s._fld7009rref
    JOIN public._reference225 employee ON employee._idrref = g._fld3223rref
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    LEFT JOIN public._reference163 document_service ON document_service._idrref = g._fld3226rref
    LEFT JOIN public._reference70 activity ON activity._idrref = document_service._fld1733rref
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
      AND s._fld7010rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea
      AND e._enumorder IN (1, 2, 3, 4)
)
SELECT state_event_at, booking_kind, recorder_tref, recorder_id, source_line_no,
       legacy_settlement_line_no, booking_document_id, lesson_start_at,
       lesson_end_at, club_id, activity_id, employee_id, service_id, client_key,
       client_code, client_name, state_order, event_category, booking_delta,
       cancelled_before_lesson, is_paid_booking
FROM pz
UNION ALL
SELECT state_event_at, booking_kind, recorder_tref, recorder_id, source_line_no,
       legacy_settlement_line_no, booking_document_id, lesson_start_at,
       lesson_end_at, club_id, activity_id, employee_id, service_id, client_key,
       client_code, client_name, state_order, event_category, booking_delta,
       cancelled_before_lesson, is_paid_booking
FROM gz;
