-- Executed only by load_contract_usage_incremental.py. $1 is text[] keys.
DELETE FROM mart.contract_usage
WHERE contract_id = ANY($1::text[]);

INSERT INTO mart.contract_usage (
    contract_id, contract_code, membership_start_date, membership_end_date,
    contract_end_month, membership_term_days, active_calendar_months, visit_count,
    usage_rate, average_monthly_visits
)
SELECT contract_id, contract_code, membership_start_date, membership_end_date,
       contract_end_month, membership_term_days, active_calendar_months, visit_count,
       usage_rate, average_monthly_visits
FROM _contract_usage_incremental_stage;
