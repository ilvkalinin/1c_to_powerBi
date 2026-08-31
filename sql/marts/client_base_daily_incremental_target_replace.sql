-- Executed only by load_client_base_daily_incremental.py inside one target
-- transaction. Bind $1 = inclusive selected-date start, $2 = exclusive end.
-- The source stage contains the exact reviewed aggregate for this range.
DELETE FROM mart.client_base_daily
WHERE report_date >= $1::date
  AND report_date < $2::date;

INSERT INTO mart.client_base_daily (
    scope_level, report_date, club_id, age_years, age_group, gender, client_count
)
SELECT scope_level, report_date, club_id, age_years, age_group, gender, client_count
FROM _client_base_daily_incremental_stage;
