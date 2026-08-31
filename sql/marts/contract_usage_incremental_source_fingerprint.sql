-- Runtime template; the runner inserts the reviewed source extract at marker.
WITH fact AS (
    /*__CONTRACT_USAGE_FACT__*/
)
SELECT contract_id,
       md5(jsonb_build_array(contract_id, contract_code, membership_start_date,
           membership_end_date, contract_end_month, membership_term_days,
           active_calendar_months, visit_count, usage_rate, average_monthly_visits)::text) AS digest_v1,
       md5(jsonb_build_array(average_monthly_visits, usage_rate, visit_count,
           active_calendar_months, membership_term_days, contract_end_month,
           membership_end_date, membership_start_date, contract_code, contract_id)::text) AS digest_v2
FROM fact
ORDER BY contract_id;
