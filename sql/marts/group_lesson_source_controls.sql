-- Narrow read-only controls for the source base of mart.group_lesson.
WITH base AS (
    SELECT g._fld3222::integer AS capacity,
           coalesce(attendance._fld8677, 0)::integer AS free_program_arrived_count
    FROM public._document279 g
    JOIN public._reference225 employee ON employee._idrref = g._fld3223rref
    LEFT JOIN public._inforg8675 attendance ON attendance._fld8676rref = g._idrref
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
      AND NOT g._marked
      AND g._fld3226rref <> '\\xbcd000505688c8b011ee0a8ba155d4a1'::bytea
)
SELECT count(*)::bigint AS lesson_rows,
       coalesce(sum(capacity), 0)::bigint AS capacity_sum,
       coalesce(sum(free_program_arrived_count), 0)::bigint AS free_arrived_sum
FROM base;
