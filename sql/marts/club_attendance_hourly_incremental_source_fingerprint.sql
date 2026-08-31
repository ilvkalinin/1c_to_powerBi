-- Runtime template. The separate runner inserts the single reviewed `hourly`
-- extract at the marker; no second business extract is maintained here.
WITH fact AS (
    /*__CLUB_ATTENDANCE_HOURLY_FACT__*/
)
SELECT visit_date,
       count(*)::bigint AS row_count,
       md5(string_agg(jsonb_build_array(visit_date, club_id, start_hour, end_hour, sex_code, age_years, visit_count, club_minutes_total)::text, E'\n'
           ORDER BY club_id, start_hour, end_hour NULLS FIRST, sex_code NULLS FIRST, age_years NULLS FIRST, visit_count, club_minutes_total)) AS digest_v1,
       md5(string_agg(jsonb_build_array(club_minutes_total, visit_count, age_years, sex_code, end_hour, start_hour, club_id, visit_date)::text, E'\x1f'
           ORDER BY club_minutes_total, visit_count, age_years NULLS FIRST, sex_code NULLS FIRST, end_hour NULLS FIRST, start_hour, club_id)) AS digest_v2
FROM fact
GROUP BY visit_date
ORDER BY visit_date;
