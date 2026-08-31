-- Stage-3 reconciliation for mart.administrator_bookings_daily.
-- Execute inside the target transaction after COPY.
-- The loader replaces @EXPECTED_SOURCE_VALUES with compact independent source
-- controls: ('branch', rows, booking_count, revenue, min_date, max_date), ...

-- AB-R01: source-to-target branch totals. Expected: all passed = true.
WITH expected_source(booking_source, expected_rows, expected_booking_count,
                     expected_revenue_amount, expected_min_lesson_date, expected_max_lesson_date) AS (
    VALUES @EXPECTED_SOURCE_VALUES
), actual_target AS (
    SELECT booking_source, count(*)::bigint AS actual_rows,
           coalesce(sum(booking_count), 0)::bigint AS actual_booking_count,
           coalesce(sum(revenue_amount), 0)::numeric(18,2) AS actual_revenue_amount,
           min(lesson_date) AS actual_min_lesson_date, max(lesson_date) AS actual_max_lesson_date
    FROM mart.administrator_bookings_daily
    GROUP BY booking_source
)
SELECT e.booking_source, e.expected_rows, a.actual_rows,
       e.expected_booking_count, a.actual_booking_count,
       e.expected_revenue_amount, a.actual_revenue_amount,
       e.expected_min_lesson_date, a.actual_min_lesson_date,
       e.expected_max_lesson_date, a.actual_max_lesson_date,
       (e.expected_rows = a.actual_rows
        AND e.expected_booking_count = a.actual_booking_count
        AND e.expected_revenue_amount = a.actual_revenue_amount
        AND e.expected_min_lesson_date IS NOT DISTINCT FROM a.actual_min_lesson_date
        AND e.expected_max_lesson_date IS NOT DISTINCT FROM a.actual_max_lesson_date) AS passed
FROM expected_source AS e
LEFT JOIN actual_target AS a USING (booking_source)
ORDER BY e.booking_source;

-- AB-R02: document-grain primary key. Expected: 0.
SELECT count(*)::bigint AS duplicate_key_groups
FROM (
    SELECT booking_source, booking_id
    FROM mart.administrator_bookings_daily
    GROUP BY booking_source, booking_id
    HAVING count(*) > 1
) AS duplicate_groups;

-- AB-R03: required, enum and range contract. Expected: all values = 0.
SELECT count(*) FILTER (WHERE booking_source NOT IN ('group', 'prebooking')
                         OR booking_id IS NULL OR btrim(booking_id) = ''
                         OR booking_created_date IS NULL OR lesson_date IS NULL OR lesson_end_date IS NULL
                         OR club_id IS NULL OR btrim(club_id) = ''
                         OR booking_author_id IS NULL OR btrim(booking_author_id) = ''
                         OR author_position_id IS NULL OR btrim(author_position_id) = ''
                         OR service_id IS NULL OR btrim(service_id) = ''
                         OR booking_count <> 1 OR revenue_amount <= 0)::bigint AS invalid_required_rows,
       count(*) FILTER (WHERE lesson_end_date < lesson_date)::bigint AS invalid_lesson_intervals
FROM mart.administrator_bookings_daily;

-- AB-R04: BR-003 horizon. Expected: 0.
SELECT count(*)::bigint AS out_of_horizon_rows
FROM mart.administrator_bookings_daily
WHERE lesson_date < @START_DATE OR lesson_date >= @END_DATE;

-- AB-R05: reference integrity for the fact itself. Expected: 0. Shared Power
-- BI dimension relationships are intentionally not asserted here: their mart
-- object names and eventual Power BI switch are outside this package (BR-036).
SELECT count(*)::bigint AS invalid_encoded_reference_rows
FROM mart.administrator_bookings_daily
WHERE club_id !~ '^[0-9a-f]{32}$'
   OR booking_author_id !~ '^[0-9a-f]{32}$'
   OR author_position_id !~ '^[0-9a-f]{32}$'
   OR service_id !~ '^[0-9a-f]{32}$'
   OR (training_format_id IS NOT NULL AND training_format_id !~ '^[0-9a-f]{32}$');

-- AB-R06: public SELECT access. Expected: 0.
SELECT count(*)::bigint AS public_select_grants
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS a
WHERE n.nspname = 'mart'
  AND c.relname = 'administrator_bookings_daily'
  AND a.grantee = 0
  AND a.privilege_type = 'SELECT';
