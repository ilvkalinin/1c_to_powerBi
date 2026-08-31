-- Executed only by load_club_attendance_hourly_incremental.py.
DELETE FROM mart.club_attendance_hourly
WHERE visit_date >= $1::date AND visit_date < $2::date;

INSERT INTO mart.club_attendance_hourly (
    visit_date, club_id, start_hour, end_hour, sex_code, age_years, visit_count, club_minutes_total
)
SELECT visit_date, club_id, start_hour, end_hour, sex_code, age_years, visit_count, club_minutes_total
FROM _club_attendance_hourly_incremental_stage;
