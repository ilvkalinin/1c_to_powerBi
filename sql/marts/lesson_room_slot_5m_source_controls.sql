-- Narrow read-only source controls for mart.lesson_room_slot_5m.
-- The runner binds dynamic BR-003 bounds to $1/$2.  This query deliberately
-- counts slots arithmetically and does not materialize the full slot series.
WITH qualified AS (
    SELECT 'group_lesson'::text AS source_kind,
           g._fld3218 AS lesson_start_at, g._fld3219 AS lesson_end_at
    FROM public._document279 AS g
    JOIN public._reference132 AS club ON club._idrref = g._fld3224rref
    JOIN public._reference225 AS employee ON employee._idrref = g._fld3223rref
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
      AND NOT g._marked
      AND g._fld3226rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
    UNION ALL
    SELECT 'prebooking'::text, p._fld4306, p._fld4307
    FROM public._document329 AS p
    JOIN public._reference132 AS club ON club._idrref = p._fld4310rref
    WHERE p._fld4306 >= $1::date AND p._fld4306 < $2::date
      AND p._posted
      AND p._fld4323rref = decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex')
      AND p._fld4321rref = decode('00000000000000000000000000000000', 'hex')
      AND NOT EXISTS (
          SELECT 1 FROM public._document313 AS cancellation
          WHERE cancellation._fld3810_rrref = p._idrref
      )
)
SELECT source_kind,
       count(*)::bigint AS source_lessons,
       count(*) FILTER (WHERE lesson_end_at <= lesson_start_at)::bigint AS nonpositive_lessons,
       coalesce(sum(
           CASE WHEN lesson_end_at > lesson_start_at
                THEN ceil(extract(epoch FROM lesson_end_at - lesson_start_at) / 300.0)::bigint
                ELSE 0 END
       ), 0)::bigint AS rounded_slot_rows
FROM qualified
GROUP BY source_kind
ORDER BY source_kind;
