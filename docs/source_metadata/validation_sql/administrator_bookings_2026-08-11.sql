-- SV-086: «Записи администраторов» — read-only source validation.
-- Execute only against gymdb with gymdb_readonly. No PII or raw identifiers are returned.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000';

-- AB-V01 expected: all 13 physical relations required by the exact current
-- SQL/M path exist in public. This is an inventory control, not a substitute
-- for source-state semantics.
SELECT count(*) AS existing_relations
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('_document283', '_document279', '_document312',
                    '_document329', '_document313', '_accumrg7575',
                    '_inforg6291', '_reference101', '_reference132',
                    '_reference163', '_reference70', '_reference225',
                    '_reference248');

-- AB-V02 expected: 100 bounded, exact-current-M group-booking rows are
-- 100 distinct booking documents. The EXISTS cancellation test must preserve
-- one row per document; cancellation is deliberately observed as current M.
WITH staff_current AS (
  SELECT DISTINCT ON (h._fld6292rref) h._fld6292rref AS employee_id
  FROM public._inforg6291 h
  JOIN public._reference101 p ON p._idrref = h._fld6296rref
  WHERE coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01 00:00:00'),
                 TIMESTAMP '2099-12-31 00:00:00') > CURRENT_TIMESTAMP
    AND p._description IN ('Администратор(Кассир)', 'Старший администратор')
  ORDER BY h._fld6292rref, h._fld6298 DESC
), base AS MATERIALIZED (
  SELECT d._idrref AS booking_id
  FROM public._document283 d
  JOIN staff_current s ON s.employee_id = d._fld644rref
  JOIN public._document279 lesson ON lesson._idrref = d._fld3291rref
  LEFT JOIN public._reference163 service ON service._idrref = lesson._fld3226rref
  LEFT JOIN public._reference248 format ON format._idrref = service._fld1803rref
  WHERE d._date_time > TIMESTAMP '2025-11-30 00:00:00'
    AND d._posted
    AND lesson._fld3218 > TIMESTAMP '2025-11-30 00:00:00'
    AND lesson._fld3228
    AND d._fld3297 > 0
    AND format._description <> 'Персональная тренировка'
    AND NOT EXISTS (
      SELECT 1
      FROM public._document312 cancel
      WHERE cancel._fld3795rref = d._fld3291rref
        AND cancel._fld3800rref = d._fld3296rref
        AND cancel._date_time > TIMESTAMP '2025-11-30 00:00:00'
        AND cancel._posted
    )
  ORDER BY d._idrref
  LIMIT 100
)
SELECT count(*) AS sampled_rows,
       count(DISTINCT booking_id) AS distinct_booking_ids,
       count(*) - count(DISTINCT booking_id) AS duplicate_booking_rows
FROM base;

-- AB-V03 expected: 100 bounded, exact-current-M preliminary-booking rows are
-- 100 distinct booking documents. The current M aggregation on Fld7581 is
-- kept intact; its row preservation is measured without adding client/service
-- predicates that would change the first release.
WITH staff_current AS (
  SELECT DISTINCT ON (h._fld6292rref) h._fld6292rref AS employee_id
  FROM public._inforg6291 h
  JOIN public._reference101 p ON p._idrref = h._fld6296rref
  WHERE coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01 00:00:00'),
                 TIMESTAMP '2099-12-31 00:00:00') > CURRENT_TIMESTAMP
    AND p._description IN ('Администратор(Кассир)', 'Старший администратор')
  ORDER BY h._fld6292rref, h._fld6298 DESC
), confirmations AS (
  SELECT a._fld7581_rrref AS booking_id, sum(a._fld7586) AS revenue_amount,
         count(*) AS movement_rows
  FROM public._accumrg7575 a
  JOIN public._reference163 service ON service._idrref = a._fld7579rref
  JOIN public._reference70 activity ON activity._idrref = service._fld1733rref
  WHERE service._fld1795rref = decode('9f007d77d46892dc47058346701d3bb6', 'hex')
    AND activity._fld843rref <> decode('9e10e872e49a551b4968a66b95c28905', 'hex')
    AND activity._fld843rref <> decode('ac626c95655c992a471b27ca8f8812cd', 'hex')
    AND service._description <> 'посещение клуба'
    AND a._period > TIMESTAMP '2025-11-30 00:00:00'
  GROUP BY a._fld7581_rrref
), base AS MATERIALIZED (
  SELECT d._idrref AS booking_id, c.movement_rows
  FROM public._document329 d
  JOIN staff_current s ON s.employee_id = d._fld644rref
  JOIN confirmations c ON c.booking_id = d._idrref AND c.revenue_amount > 0
  LEFT JOIN public._reference163 service ON service._idrref = d._fld4316rref
  LEFT JOIN public._reference248 format ON format._idrref = service._fld1803rref
  WHERE d._date_time > TIMESTAMP '2025-11-30 00:00:00'
    AND d._fld4306 < CURRENT_DATE
    AND d._posted
    AND d._fld4311 > 0
    AND format._description IN ('Групповое занятие', 'Платный урок')
    AND NOT EXISTS (
      SELECT 1 FROM public._document313 cancel
      WHERE cancel._fld3810_rrref = d._idrref
        AND cancel._date_time > TIMESTAMP '2025-11-30 00:00:00'
        AND cancel._posted
    )
  ORDER BY d._idrref
  LIMIT 100
)
SELECT count(*) AS sampled_rows,
       count(DISTINCT booking_id) AS distinct_booking_ids,
       count(*) - count(DISTINCT booking_id) AS duplicate_booking_rows,
       count(*) FILTER (WHERE movement_rows > 1) AS bookings_with_multiple_movements,
       coalesce(max(movement_rows), 0) AS max_movements_per_booking
FROM base;

-- AB-V04 expected: each bounded document has its historical employment
-- cardinality measured at document creation. No 1:1 outcome is assumed;
-- a zero or multiple match is evidence against silently replacing current M.
WITH candidates AS MATERIALIZED (
  (
    SELECT 'group'::text AS source_kind, d._idrref AS booking_id,
           d._fld644rref AS author_id, d._date_time AS created_at
    FROM public._document283 d
    WHERE d._date_time > TIMESTAMP '2025-11-30 00:00:00'
    ORDER BY d._idrref LIMIT 100
  )
  UNION ALL
  (
    SELECT 'prebooking', d._idrref, d._fld644rref, d._date_time
    FROM public._document329 d
    WHERE d._date_time > TIMESTAMP '2025-11-30 00:00:00'
    ORDER BY d._idrref LIMIT 100
  )
), matches AS (
  SELECT c.source_kind, c.booking_id, count(p._idrref) AS employment_rows
  FROM candidates c
  LEFT JOIN public._inforg6291 h
    ON h._fld6292rref = c.author_id
   AND h._fld6298 <= c.created_at
   AND coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01 00:00:00'),
                TIMESTAMP '2099-12-31 00:00:00') >= c.created_at
  LEFT JOIN public._reference101 p ON p._idrref = h._fld6296rref
    AND p._description IN ('Администратор(Кассир)', 'Старший администратор')
  GROUP BY 1, 2
)
SELECT source_kind, count(*) AS sampled_bookings,
       count(*) FILTER (WHERE employment_rows = 0) AS no_historical_admin_match,
       count(*) FILTER (WHERE employment_rows = 1) AS one_historical_admin_match,
       count(*) FILTER (WHERE employment_rows > 1) AS multiple_historical_admin_matches,
       max(employment_rows) AS max_historical_admin_matches
FROM matches
GROUP BY 1 ORDER BY 1;

ROLLBACK;
