WITH fact AS (
    SELECT visit_date, club_id, start_hour, end_hour, sex_code, age_years, visit_count, club_minutes_total
    FROM mart.club_attendance_hourly
    WHERE visit_date >= $1::date AND visit_date < $2::date
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
