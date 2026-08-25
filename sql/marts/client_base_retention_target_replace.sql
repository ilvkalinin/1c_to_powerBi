-- Runner-owned target transaction. Bind $1/$2 to the exact report-date horizon.
DELETE FROM mart.client_base_retention
WHERE report_date >= $1::date AND report_date < $2::date;

INSERT INTO mart.client_base_retention (
    scope_level, report_date, comparison_type, comparison_date,
    baseline_club_id, current_age_years, current_age_group, current_gender,
    current_membership_tenure, baseline_client_count, retained_client_count
)
SELECT scope_level, report_date, comparison_type, comparison_date,
       baseline_club_id, current_age_years, current_age_group, current_gender,
       current_membership_tenure, baseline_client_count, retained_client_count
FROM _client_base_retention_stage;
