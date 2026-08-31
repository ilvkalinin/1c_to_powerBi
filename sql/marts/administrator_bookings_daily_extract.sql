-- Immutable PBIT-compatible source extract for mart.administrator_bookings_daily.
-- $1/$2 are lesson_date bounds. Execute only on VM-1 in REPEATABLE READ, READ ONLY.
WITH prebooking_in_window AS (
    SELECT d._idrref AS booking_ref
    FROM public._document329 AS d
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
), current_admin AS (
    SELECT DISTINCT ON (h._fld6292rref)
        h._fld6292rref AS author_ref,
        h._fld6296rref AS position_ref
    FROM public._inforg6291 AS h
    JOIN public._reference101 AS position ON position._idrref = h._fld6296rref
    WHERE coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01 00:00:00'),
                   TIMESTAMP '2099-12-31 00:00:00') > CURRENT_TIMESTAMP
      AND position._description IN ('Администратор(Кассир)', 'Старший администратор')
    ORDER BY h._fld6292rref, h._fld6298 DESC
), prebooking_equity AS (
    SELECT a._fld7581_rrref AS booking_ref, sum(a._fld7586)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7575 AS a
    JOIN prebooking_in_window AS window_booking ON window_booking.booking_ref = a._fld7581_rrref
    JOIN public._reference163 AS service ON service._idrref = a._fld7579rref
    JOIN public._reference70 AS activity ON activity._idrref = service._fld1733rref
    WHERE service._fld1795rref = decode('9f007d77d46892dc47058346701d3bb6', 'hex')
      AND activity._fld843rref NOT IN (
          decode('9e10e872e49a551b4968a66b95c28905', 'hex'),
          decode('ac626c95655c992a471b27ca8f8812cd', 'hex')
      )
      AND cast(service._description AS varchar(1000)) <> 'посещение клуба'
      AND a._period > TIMESTAMP '2025-11-30 00:00:00'
    GROUP BY a._fld7581_rrref
), group_branch AS (
    SELECT
        'group'::text AS booking_source,
        encode(d._idrref, 'hex') AS booking_id,
        d._date_time::date AS booking_created_date,
        lesson._fld3218::date AS lesson_date,
        lesson._fld3219::date AS lesson_end_date,
        encode(lesson._fld3224rref, 'hex') AS club_id,
        encode(d._fld644rref, 'hex') AS booking_author_id,
        encode(admin.position_ref, 'hex') AS author_position_id,
        encode(lesson._fld3226rref, 'hex') AS service_id,
        encode(service._fld1803rref, 'hex') AS training_format_id,
        1::bigint AS booking_count,
        d._fld3297::numeric(18, 2) AS revenue_amount
    FROM public._document283 AS d
    JOIN current_admin AS admin ON admin.author_ref = d._fld644rref
    JOIN public._document279 AS lesson ON lesson._idrref = d._fld3291rref
    LEFT JOIN public._reference163 AS service ON service._idrref = lesson._fld3226rref
    LEFT JOIN public._reference248 AS format ON format._idrref = service._fld1803rref
    WHERE d._date_time > TIMESTAMP '2025-11-30 00:00:00'
      AND d._posted
      AND lesson._fld3218 >= $1::date AND lesson._fld3218 < $2::date
      AND lesson._fld3228
      AND d._fld3297 > 0
      AND cast(format._description AS varchar(1000)) <> 'Персональная тренировка'
      AND NOT EXISTS (
          SELECT 1 FROM public._document312 AS cancelled
          WHERE cancelled._fld3795rref = d._fld3291rref
            AND cancelled._fld3800rref = d._fld3296rref
            AND cancelled._date_time > TIMESTAMP '2025-11-30 00:00:00'
            AND cancelled._posted
      )
), prebooking_branch AS (
    SELECT
        'prebooking'::text AS booking_source,
        encode(d._idrref, 'hex') AS booking_id,
        d._date_time::date AS booking_created_date,
        d._fld4306::date AS lesson_date,
        d._fld4307::date AS lesson_end_date,
        encode(d._fld4310rref, 'hex') AS club_id,
        encode(d._fld644rref, 'hex') AS booking_author_id,
        encode(admin.position_ref, 'hex') AS author_position_id,
        encode(d._fld4316rref, 'hex') AS service_id,
        encode(service._fld1803rref, 'hex') AS training_format_id,
        1::bigint AS booking_count,
        equity.revenue_amount
    FROM public._document329 AS d
    JOIN current_admin AS admin ON admin.author_ref = d._fld644rref
    JOIN prebooking_equity AS equity ON equity.booking_ref = d._idrref AND equity.revenue_amount > 0
    LEFT JOIN public._reference163 AS service ON service._idrref = d._fld4316rref
    LEFT JOIN public._reference248 AS format ON format._idrref = service._fld1803rref
    WHERE d._date_time > TIMESTAMP '2025-11-30 00:00:00'
      AND d._fld4306 >= $1::date AND d._fld4306 < $2::date
      AND d._fld4306 < CURRENT_DATE
      AND d._posted
      AND d._fld4311 > 0
      AND cast(format._description AS varchar(1000)) IN ('Групповое занятие', 'Платный урок')
      AND NOT EXISTS (
          SELECT 1 FROM public._document313 AS cancelled
          WHERE cancelled._fld3810_rrref = d._idrref
            AND cancelled._date_time > TIMESTAMP '2025-11-30 00:00:00'
            AND cancelled._posted
      )
)
SELECT booking_source, booking_id, booking_created_date, lesson_date,
       lesson_end_date, club_id, booking_author_id, author_position_id,
       service_id, training_format_id, booking_count, revenue_amount
FROM group_branch
UNION ALL
SELECT booking_source, booking_id, booking_created_date, lesson_date,
       lesson_end_date, club_id, booking_author_id, author_position_id,
       service_id, training_format_id, booking_count, revenue_amount
FROM prebooking_branch;
