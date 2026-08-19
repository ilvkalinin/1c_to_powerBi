-- Approved-run target transaction for mart.client_base_daily.
-- The runner opens the transaction, obtains the advisory lock, creates the
-- stage and expected-control tables, then streams the source aggregate here.
-- Bind $1 = inclusive BR-003 horizon start, $2 = exclusive horizon end.

DELETE FROM mart.client_base_daily
WHERE report_date >= $1::date
  AND report_date < $2::date;

INSERT INTO mart.client_base_daily (
    scope_level, report_date, club_id, age_years, age_group, gender, client_count
)
SELECT scope_level, report_date, club_id, age_years, age_group, gender, client_count
FROM _client_base_daily_stage;
