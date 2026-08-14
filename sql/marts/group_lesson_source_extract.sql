-- Read-only base extract for mart.group_lesson. The runner binds BR-003
-- bounds to $1/$2. State aggregates come from mart.prebooking_state_event,
-- not from a duplicate raw InfoRg7006 implementation.
SELECT encode(g._idrref, 'hex') AS group_lesson_id,
       g._date_time AS lesson_created_at,
       g._fld3218 AS lesson_start_at,
       g._fld3219 AS lesson_end_at,
       encode(g._fld3224rref, 'hex') AS club_id,
       CASE WHEN activity._idrref IS NULL THEN NULL ELSE encode(service._fld1733rref, 'hex') END AS activity_id,
       encode(g._fld3223rref, 'hex') AS employee_id,
       encode(g._fld3226rref, 'hex') AS service_id,
       g._fld3222::integer AS capacity,
       (service._fld1778 IS TRUE) AS is_free_program,
       coalesce(attendance._fld8677, 0)::integer AS free_program_arrived_count
FROM public._document279 g
JOIN public._reference225 employee ON employee._idrref = g._fld3223rref
LEFT JOIN public._reference163 service ON service._idrref = g._fld3226rref
LEFT JOIN public._reference70 activity ON activity._idrref = service._fld1733rref
LEFT JOIN public._inforg8675 attendance ON attendance._fld8676rref = g._idrref
WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
  AND NOT g._marked
  AND g._fld3226rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea;
