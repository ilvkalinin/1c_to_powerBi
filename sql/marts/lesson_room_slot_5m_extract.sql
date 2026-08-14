-- Read-only extract for mart.lesson_room_slot_5m.
-- The runner binds the dynamic BR-003 bounds to $1/$2.
-- BR-021 rounds only positive incomplete intervals up to their final 5-minute slot.
WITH qualified AS (
    SELECT 'group_lesson'::text AS source_kind,
           encode(g._idrref, 'hex') AS source_lesson_id,
           g._date_time AS created_at,
           g._fld3218 AS lesson_start_at,
           g._fld3219 AS lesson_end_at,
           encode(g._fld3224rref, 'hex') AS club_id,
           CASE WHEN room._idrref IS NULL THEN NULL ELSE encode(g._fld3227rref, 'hex') END AS room_id,
           encode(g._fld3223rref, 'hex') AS employee_id,
           CASE WHEN service._idrref IS NULL THEN NULL ELSE encode(g._fld3226rref, 'hex') END AS service_id,
           CASE WHEN activity._idrref IS NULL THEN NULL ELSE encode(service._fld1733rref, 'hex') END AS activity_id,
           CASE WHEN training_format._idrref IS NULL THEN NULL ELSE encode(service._fld1803rref, 'hex') END AS training_format_id,
           CASE WHEN service._fld1778 IS TRUE THEN 'club_time' ELSE 'paid' END AS payment_class_current,
           CASE WHEN g._date_time > g._fld3219 THEN 'after' ELSE 'before_or_at_end' END AS schedule_entry_timeliness,
           NULL::boolean AS is_cancelled_current
    FROM public._document279 AS g
    JOIN public._reference132 AS club ON club._idrref = g._fld3224rref
    JOIN public._reference225 AS employee ON employee._idrref = g._fld3223rref
    LEFT JOIN public._reference191 AS room ON room._idrref = g._fld3227rref
    LEFT JOIN public._reference163 AS service ON service._idrref = g._fld3226rref
    LEFT JOIN public._reference70 AS activity ON activity._idrref = service._fld1733rref
    LEFT JOIN public._reference248 AS training_format ON training_format._idrref = service._fld1803rref
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
      AND NOT g._marked
      AND g._fld3226rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
), prebooking AS (
    SELECT 'prebooking'::text AS source_kind,
           encode(p._idrref, 'hex') AS source_lesson_id,
           p._date_time AS created_at,
           p._fld4306 AS lesson_start_at,
           p._fld4307 AS lesson_end_at,
           encode(p._fld4310rref, 'hex') AS club_id,
           CASE WHEN room._idrref IS NULL THEN NULL ELSE encode(p._fld4320rref, 'hex') END AS room_id,
           CASE WHEN employee._idrref IS NULL THEN NULL ELSE encode(p._fld4322rref, 'hex') END AS employee_id,
           CASE WHEN service._idrref IS NULL THEN NULL ELSE encode(p._fld4316rref, 'hex') END AS service_id,
           CASE WHEN activity._idrref IS NULL THEN NULL ELSE encode(service._fld1733rref, 'hex') END AS activity_id,
           CASE WHEN training_format._idrref IS NULL THEN NULL ELSE encode(service._fld1803rref, 'hex') END AS training_format_id,
           CASE
             WHEN service._idrref IS NULL THEN 'reserve'
             WHEN service._fld1778 IS TRUE THEN 'club_time'
             ELSE 'paid'
           END AS payment_class_current,
           CASE WHEN p._date_time > p._fld4307 THEN 'after' ELSE 'before_or_at_end' END AS schedule_entry_timeliness,
           FALSE AS is_cancelled_current
    FROM public._document329 AS p
    JOIN public._reference132 AS club ON club._idrref = p._fld4310rref
    LEFT JOIN public._reference191 AS room ON room._idrref = p._fld4320rref
    LEFT JOIN public._reference225 AS employee ON employee._idrref = p._fld4322rref
    LEFT JOIN public._reference163 AS service ON service._idrref = p._fld4316rref
    LEFT JOIN public._reference70 AS activity ON activity._idrref = service._fld1733rref
    LEFT JOIN public._reference248 AS training_format ON training_format._idrref = service._fld1803rref
    WHERE p._fld4306 >= $1::date AND p._fld4306 < $2::date
      AND p._posted
      AND p._fld4323rref = decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex')
      AND p._fld4321rref = decode('00000000000000000000000000000000', 'hex')
      AND NOT EXISTS (
          SELECT 1 FROM public._document313 AS cancellation
          WHERE cancellation._fld3810_rrref = p._idrref
      )
), lessons AS (
    SELECT * FROM qualified
    UNION ALL
    SELECT * FROM prebooking
), positive AS (
    SELECT l.*, ceil(extract(epoch FROM l.lesson_end_at - l.lesson_start_at) / 300.0)::integer AS slot_count
    FROM lessons AS l
    WHERE l.lesson_end_at > l.lesson_start_at
)
SELECT p.source_kind, p.source_lesson_id, p.created_at, p.lesson_start_at,
       p.lesson_end_at, s.slot_start_at, p.club_id, p.room_id, p.employee_id,
       p.service_id, p.activity_id, p.training_format_id, p.payment_class_current,
       p.schedule_entry_timeliness, p.is_cancelled_current, 1::smallint AS occupied_slot_count
FROM positive AS p
CROSS JOIN LATERAL generate_series(
    p.lesson_start_at,
    p.lesson_start_at + (p.slot_count - 1) * interval '5 minutes',
    interval '5 minutes'
) AS s(slot_start_at);
