-- Narrow read-only source controls for mart.prebooking_state_event.
-- This preserves every current-rule inclusion join and predicate, but avoids
-- building presentation attributes solely to calculate the five load controls.
WITH pz AS (
    SELECT e._enumorder::smallint AS state_order,
           CASE WHEN e._enumorder = 1 THEN 1 ELSE -1 END::smallint AS booking_delta
    FROM public._inforg7006 s
    JOIN public._document329 p ON p._idrref = s._fld7007_rrref
    JOIN public._reference141x1 client ON client._idrref = s._fld7008rref
    JOIN public._reference132 club ON club._idrref = s._fld7009rref
    JOIN public._reference225 employee ON employee._idrref = p._fld4322rref
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    LEFT JOIN public._document329_vt4352 v ON v._document329_idrref = p._idrref
    LEFT JOIN public._reference163 document_service ON document_service._idrref = p._fld4316rref
    WHERE p._fld4306 >= $1::date AND p._fld4306 < $2::date
      AND s._fld7010rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea
      AND v._fld4358rref <> '\\xa0f1524d502e0d5d4c1dfeb9d5bbb3fe'::bytea
      AND e._enumorder IN (1, 2, 3)
      AND document_service._parentidrref IS DISTINCT FROM '\\x4296a4bf013441d111e7cae05001072c'::bytea
), gz AS (
    SELECT e._enumorder::smallint AS state_order,
           CASE WHEN e._enumorder = 1 THEN 1 WHEN e._enumorder IN (2, 3) THEN -1 ELSE 0 END::smallint AS booking_delta
    FROM public._inforg7006 s
    JOIN public._document279 g ON g._idrref = s._fld7007_rrref
    JOIN public._reference141x1 client ON client._idrref = s._fld7008rref
    JOIN public._reference132 club ON club._idrref = s._fld7009rref
    JOIN public._reference225 employee ON employee._idrref = g._fld3223rref
    JOIN public._enum448 e ON e._idrref = s._fld7013rref
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
      AND s._fld7010rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea
      AND e._enumorder IN (1, 2, 3, 4)
), source_rows AS (
    SELECT 'PZ'::text AS booking_kind, state_order, booking_delta FROM pz
    UNION ALL
    SELECT 'GZ'::text, state_order, booking_delta FROM gz
)
SELECT count(*)::bigint AS target_rows,
       coalesce(sum(booking_delta), 0)::bigint AS booking_delta,
       count(*) FILTER (WHERE booking_kind = 'PZ')::bigint AS pz_rows,
       count(*) FILTER (WHERE booking_kind = 'GZ')::bigint AS gz_rows,
       count(*) FILTER (WHERE state_order = 4)::bigint AS arrived_rows
FROM source_rows;
