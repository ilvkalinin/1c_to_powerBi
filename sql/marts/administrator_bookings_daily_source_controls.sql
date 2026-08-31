-- Independent source controls for mart.administrator_bookings_daily.
-- Bind $1/$2 to the same BR-003 lesson-date window as the extract.
-- Execute on VM-1 inside one REPEATABLE READ, READ ONLY snapshot before COPY.
-- The controls return aggregate values only; no PII or document identifiers.

-- name: expected_totals
WITH prebooking_in_window AS (
    SELECT d._idrref AS booking_ref
    FROM public._document329 AS d
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
), active_admin AS (
    SELECT DISTINCT ON (h._fld6292rref)
        h._fld6292rref AS author_ref,
        h._fld6296rref AS position_ref
    FROM public._inforg6291 AS h
    JOIN public._reference101 AS p ON p._idrref = h._fld6296rref
    WHERE coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01 00:00:00'),
                   TIMESTAMP '2099-12-31 00:00:00') > CURRENT_TIMESTAMP
      AND p._description IN ('Администратор(Кассир)', 'Старший администратор')
    ORDER BY h._fld6292rref, h._fld6298 DESC
), prebooking_amount AS (
    SELECT m._fld7581_rrref AS booking_ref,
           sum(m._fld7586)::numeric(18, 2) AS revenue_amount,
           count(*)::bigint AS movement_rows
    FROM public._accumrg7575 AS m
    JOIN prebooking_in_window AS window_booking ON window_booking.booking_ref = m._fld7581_rrref
    JOIN public._reference163 AS movement_service ON movement_service._idrref = m._fld7579rref
    JOIN public._reference70 AS activity ON activity._idrref = movement_service._fld1733rref
    WHERE movement_service._fld1795rref = decode('9f007d77d46892dc47058346701d3bb6', 'hex')
      AND activity._fld843rref NOT IN (
          decode('9e10e872e49a551b4968a66b95c28905', 'hex'),
          decode('ac626c95655c992a471b27ca8f8812cd', 'hex')
      )
      AND cast(movement_service._description AS varchar(1000)) <> 'посещение клуба'
      AND m._period > TIMESTAMP '2025-11-30 00:00:00'
    GROUP BY m._fld7581_rrref
), expected AS (
    SELECT 'group'::text AS booking_source, d._idrref AS booking_ref,
           lesson._fld3218::date AS lesson_date,
           d._fld3297::numeric(18, 2) AS revenue_amount,
           1::bigint AS booking_count
    FROM public._document279 AS lesson
    JOIN public._document283 AS d ON d._fld3291rref = lesson._idrref
    JOIN active_admin AS admin ON admin.author_ref = d._fld644rref
    LEFT JOIN public._reference163 AS service ON service._idrref = lesson._fld3226rref
    LEFT JOIN public._reference248 AS training_format ON training_format._idrref = service._fld1803rref
    WHERE lesson._fld3218 >= $1::date AND lesson._fld3218 < $2::date
      AND d._date_time > TIMESTAMP '2025-11-30 00:00:00'
      AND d._posted
      AND lesson._fld3228
      AND d._fld3297 > 0
      AND cast(training_format._description AS varchar(1000)) <> 'Персональная тренировка'
      AND NOT EXISTS (
          SELECT 1
          FROM public._document312 AS cancellation
          WHERE cancellation._fld3795rref = d._fld3291rref
            AND cancellation._fld3800rref = d._fld3296rref
            AND cancellation._date_time > TIMESTAMP '2025-11-30 00:00:00'
            AND cancellation._posted
      )
    UNION ALL
    SELECT 'prebooking', d._idrref, d._fld4306::date, amount.revenue_amount, 1::bigint
    FROM public._document329 AS d
    JOIN active_admin AS admin ON admin.author_ref = d._fld644rref
    JOIN prebooking_amount AS amount ON amount.booking_ref = d._idrref
    LEFT JOIN public._reference163 AS service ON service._idrref = d._fld4316rref
    LEFT JOIN public._reference248 AS training_format ON training_format._idrref = service._fld1803rref
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
      AND d._date_time > TIMESTAMP '2025-11-30 00:00:00'
      AND d._fld4306 < CURRENT_DATE
      AND d._posted
      AND d._fld4311 > 0
      AND amount.revenue_amount > 0
      AND cast(training_format._description AS varchar(1000)) IN ('Групповое занятие', 'Платный урок')
      AND NOT EXISTS (
          SELECT 1
          FROM public._document313 AS cancellation
          WHERE cancellation._fld3810_rrref = d._idrref
            AND cancellation._date_time > TIMESTAMP '2025-11-30 00:00:00'
            AND cancellation._posted
      )
)
SELECT booking_source,
       count(*)::bigint AS expected_rows,
       count(DISTINCT booking_ref)::bigint AS expected_distinct_bookings,
       coalesce(sum(booking_count), 0)::bigint AS expected_booking_count,
       coalesce(sum(revenue_amount), 0)::numeric(18, 2) AS expected_revenue_amount,
       min(lesson_date) AS min_lesson_date,
       max(lesson_date) AS max_lesson_date
FROM expected
GROUP BY booking_source
ORDER BY booking_source;

-- name: source_invariants
WITH prebooking_in_window AS (
    SELECT d._idrref AS booking_ref
    FROM public._document329 AS d
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
), active_admin AS (
    SELECT DISTINCT ON (h._fld6292rref)
        h._fld6292rref AS author_ref,
        h._fld6296rref AS position_ref
    FROM public._inforg6291 AS h
    JOIN public._reference101 AS p ON p._idrref = h._fld6296rref
    WHERE coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01 00:00:00'),
                   TIMESTAMP '2099-12-31 00:00:00') > CURRENT_TIMESTAMP
      AND p._description IN ('Администратор(Кассир)', 'Старший администратор')
    ORDER BY h._fld6292rref, h._fld6298 DESC
), prebooking_amount AS (
    SELECT m._fld7581_rrref AS booking_ref, sum(m._fld7586)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7575 AS m
    JOIN prebooking_in_window AS window_booking ON window_booking.booking_ref = m._fld7581_rrref
    JOIN public._reference163 AS movement_service ON movement_service._idrref = m._fld7579rref
    JOIN public._reference70 AS activity ON activity._idrref = movement_service._fld1733rref
    WHERE movement_service._fld1795rref = decode('9f007d77d46892dc47058346701d3bb6', 'hex')
      AND activity._fld843rref NOT IN (decode('9e10e872e49a551b4968a66b95c28905', 'hex'),
                                        decode('ac626c95655c992a471b27ca8f8812cd', 'hex'))
      AND cast(movement_service._description AS varchar(1000)) <> 'посещение клуба'
      AND m._period > TIMESTAMP '2025-11-30 00:00:00'
    GROUP BY m._fld7581_rrref
), expected AS (
    SELECT 'group'::text AS booking_source, d._idrref AS booking_ref,
           d._date_time::date AS booking_created_date, lesson._fld3218::date AS lesson_date,
           lesson._fld3219::date AS lesson_end_date, lesson._fld3224rref AS club_ref,
           d._fld644rref AS author_ref, admin.position_ref, lesson._fld3226rref AS service_ref,
           service._fld1803rref AS format_ref, d._fld3297::numeric(18, 2) AS revenue_amount,
           EXISTS (SELECT 1 FROM public._document312 AS cancellation
                   WHERE cancellation._fld3795rref = d._fld3291rref
                     AND cancellation._fld3800rref = d._fld3296rref
                     AND cancellation._date_time > TIMESTAMP '2025-11-30 00:00:00'
                     AND cancellation._posted) AS included_cancellation
    FROM public._document283 AS d
    JOIN public._document279 AS lesson ON lesson._idrref = d._fld3291rref
    JOIN active_admin AS admin ON admin.author_ref = d._fld644rref
    LEFT JOIN public._reference163 AS service ON service._idrref = lesson._fld3226rref
    LEFT JOIN public._reference248 AS training_format ON training_format._idrref = service._fld1803rref
    WHERE lesson._fld3218 >= $1::date AND lesson._fld3218 < $2::date
      AND d._date_time > TIMESTAMP '2025-11-30 00:00:00' AND d._posted AND lesson._fld3228
      AND d._fld3297 > 0 AND cast(training_format._description AS varchar(1000)) <> 'Персональная тренировка'
      AND NOT EXISTS (SELECT 1 FROM public._document312 AS cancellation
                      WHERE cancellation._fld3795rref = d._fld3291rref
                        AND cancellation._fld3800rref = d._fld3296rref
                        AND cancellation._date_time > TIMESTAMP '2025-11-30 00:00:00'
                        AND cancellation._posted)
    UNION ALL
    SELECT 'prebooking', d._idrref, d._date_time::date, d._fld4306::date, d._fld4307::date,
           d._fld4310rref, d._fld644rref, admin.position_ref, d._fld4316rref,
           service._fld1803rref, amount.revenue_amount,
           EXISTS (SELECT 1 FROM public._document313 AS cancellation
                   WHERE cancellation._fld3810_rrref = d._idrref
                     AND cancellation._date_time > TIMESTAMP '2025-11-30 00:00:00'
                     AND cancellation._posted)
    FROM public._document329 AS d
    JOIN active_admin AS admin ON admin.author_ref = d._fld644rref
    JOIN prebooking_amount AS amount ON amount.booking_ref = d._idrref
    LEFT JOIN public._reference163 AS service ON service._idrref = d._fld4316rref
    LEFT JOIN public._reference248 AS training_format ON training_format._idrref = service._fld1803rref
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
      AND d._date_time > TIMESTAMP '2025-11-30 00:00:00' AND d._fld4306 < CURRENT_DATE
      AND d._posted AND d._fld4311 > 0 AND amount.revenue_amount > 0
      AND cast(training_format._description AS varchar(1000)) IN ('Групповое занятие', 'Платный урок')
      AND NOT EXISTS (SELECT 1 FROM public._document313 AS cancellation
                      WHERE cancellation._fld3810_rrref = d._idrref
                        AND cancellation._date_time > TIMESTAMP '2025-11-30 00:00:00'
                        AND cancellation._posted)
)
SELECT count(*) - count(DISTINCT (booking_source, booking_ref)) AS duplicate_source_keys,
       count(*) FILTER (WHERE booking_created_date IS NULL OR lesson_date IS NULL OR lesson_end_date IS NULL
                         OR club_ref IS NULL OR author_ref IS NULL OR position_ref IS NULL OR service_ref IS NULL
                         OR revenue_amount IS NULL OR revenue_amount <= 0) AS invalid_required_values,
       count(*) FILTER (WHERE lesson_end_date < lesson_date) AS invalid_lesson_intervals,
       count(*) FILTER (WHERE included_cancellation) AS included_cancelled_rows,
       count(*) FILTER (WHERE lesson_date < $1::date OR lesson_date >= $2::date) AS out_of_horizon_rows
FROM expected;
