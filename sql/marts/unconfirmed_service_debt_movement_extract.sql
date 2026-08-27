-- Exact current-M-compatible movement projection. $1/$2 are BR-003 bounds.
WITH base AS MATERIALIZED (
    SELECT r._period AS debt_event_at,
           r._recordertref AS recorder_type, r._recorderrref AS recorder_id,
           r._lineno::integer AS recorder_line_no, r._recordkind::smallint AS record_kind,
           r._fld7511rref AS client_key, r._fld7510rref AS club_id,
           r._fld7512_rrref AS prebooking_id, r._fld7513rref AS service_id,
           r._fld7514 AS service_start_at, r._fld7515 AS service_end_at,
           r._fld7516 AS quantity_delta,
           CASE WHEN r._recordkind = 1 THEN -r._fld7517 ELSE r._fld7517 END AS amount_delta
    FROM public._accumrg7509 r
    JOIN public._reference163 service ON service._idrref = r._fld7513rref
    WHERE r._period >= $1::timestamp AND r._period < $2::timestamp
      AND service._description::text NOT ILIKE 'Купон%'
), prebooking_branch AS (
    SELECT b.*, club._description::text AS club_name, client._code::text AS client_code,
           client._description::text AS client_name, service._description::text AS service_name,
           employee._idrref AS employee_id, employee._description::text AS employee_name
    FROM base b
    JOIN public._document329 booking ON booking._idrref = b.prebooking_id
    JOIN public._reference225 employee ON employee._idrref = booking._fld4322rref
    LEFT JOIN public._reference132 club ON club._idrref = b.club_id
    LEFT JOIN public._reference141x1 client ON client._idrref = b.client_key
    JOIN public._reference163 service ON service._idrref = b.service_id
), group_branch AS (
    SELECT b.*, club._description::text AS club_name, client._code::text AS client_code,
           client._description::text AS client_name, service._description::text AS service_name,
           employee._idrref AS employee_id, employee._description::text AS employee_name
    FROM base b
    JOIN public._document279 booking ON booking._idrref = b.prebooking_id
    JOIN public._reference225 employee ON employee._idrref = booking._fld3223rref
    LEFT JOIN public._reference132 club ON club._idrref = b.club_id
    LEFT JOIN public._reference141x1 client ON client._idrref = b.client_key
    JOIN public._reference163 service ON service._idrref = b.service_id
)
SELECT debt_event_at, recorder_type, recorder_id, recorder_line_no, record_kind,
       client_key, client_code, client_name, club_id, club_name, prebooking_id,
       service_id, service_name, employee_id, employee_name, service_start_at,
       service_end_at, quantity_delta, amount_delta
FROM prebooking_branch
UNION ALL
SELECT debt_event_at, recorder_type, recorder_id, recorder_line_no, record_kind,
       client_key, client_code, client_name, club_id, club_name, prebooking_id,
       service_id, service_name, employee_id, employee_name, service_start_at,
       service_end_at, quantity_delta, amount_delta
FROM group_branch;
