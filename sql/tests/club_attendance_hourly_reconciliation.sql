-- Stage-3 reconciliation for mart.club_attendance_hourly.
-- Execute inside the target transaction after COPY.
-- $1 = expected aggregate rows; $2 = expected source visit rows;
-- $3 = expected source minutes rounded to six decimals; $4/$5 = BR-003 dates.

-- WA-R01: transport completeness and source-side additivity. Expected: passed = true.
SELECT $1::bigint AS expected_hourly_rows,
       $2::bigint AS expected_source_visit_rows,
       $3::numeric AS expected_source_minutes_total,
       (SELECT count(*)::bigint FROM mart.club_attendance_hourly) AS actual_hourly_rows,
       (SELECT coalesce(sum(visit_count), 0)::bigint FROM mart.club_attendance_hourly) AS actual_visit_rows,
       (SELECT round(coalesce(sum(club_minutes_total), 0)::numeric, 6) FROM mart.club_attendance_hourly)
           AS actual_minutes_total,
       ($1::bigint = (SELECT count(*) FROM mart.club_attendance_hourly)
        AND $2::bigint = (SELECT coalesce(sum(visit_count), 0) FROM mart.club_attendance_hourly)
        AND $3::numeric = (SELECT round(coalesce(sum(club_minutes_total), 0)::numeric, 6)
                           FROM mart.club_attendance_hourly)) AS passed;

-- WA-R02: logical hourly grain uniqueness. Expected: 0.
SELECT count(*)::bigint AS duplicate_grain_groups
FROM (
    SELECT visit_date, club_id, start_hour, end_hour, sex_code, age_years
    FROM mart.club_attendance_hourly
    GROUP BY 1, 2, 3, 4, 5, 6
    HAVING count(*) > 1
) AS duplicate_groups;

-- WA-R03: physical contract. Expected: all values = 0.
SELECT count(*) FILTER (WHERE visit_date IS NULL OR club_id IS NULL OR btrim(club_id) = ''
                             OR start_hour NOT BETWEEN 0 AND 23 OR visit_count <= 0)::bigint AS invalid_required_rows,
       count(*) FILTER (WHERE end_hour IS NOT NULL AND end_hour NOT BETWEEN 0 AND 23)::bigint
           AS invalid_end_hour_rows
FROM mart.club_attendance_hourly;

-- WA-R04: BR-003 horizon. Expected: 0.
SELECT count(*)::bigint AS out_of_horizon_rows
FROM mart.club_attendance_hourly
WHERE visit_date < $4::date OR visit_date >= $5::date;

-- WA-R05: BR-019 sentinel transformation. Expected: 0.
SELECT count(*)::bigint AS untransformed_sentinel_age_rows
FROM mart.club_attendance_hourly
WHERE age_years = 2025;

-- WA-R06: access boundary. Expected: 0.
SELECT count(*)::bigint AS public_select_grants
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS a
WHERE n.nspname = 'mart'
  AND c.relname = 'club_attendance_hourly'
  AND a.grantee = 0
  AND a.privilege_type = 'SELECT';
