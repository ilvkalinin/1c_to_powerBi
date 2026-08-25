-- Runner-owned target transaction. Bind $1/$2 to the exact report-date horizon.
DELETE FROM mart.client_base_snapshot
WHERE report_date >= $1::date AND report_date < $2::date;

INSERT INTO mart.client_base_snapshot (
    scope_level, report_date, club_id, age_years, age_group, gender,
    membership_tenure, activity_bucket, client_count
)
SELECT scope_level, report_date, club_id, age_years, age_group, gender,
       membership_tenure, activity_bucket, client_count
FROM _client_base_snapshot_stage;
