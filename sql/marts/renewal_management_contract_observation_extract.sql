-- Reviewed derived source for mart.renewal_management_contract_observation.
-- Current VM-2 mart only; no VM-1 raw source and no PII fields.
SELECT
    m.expiring_contract_id,
    m.membership_end_date,
    m.contract_end_month,
    m.client_id,
    m.access_club_id,
    m.next_contract_id,
    m.next_contract_code,
    m.renewal_activation_date,
    m.next_contract_start_date,
    m.next_contract_term_days,
    m.renewal_type,
    m.renewed_by_month_close_flag,
    m.renewed_current_flag,
    m.renewal_lead_lag_days,
    m.return_days,
    m.return_bucket,
    m.current_rating,
    m.current_tenure,
    m.last_interaction_at,
    m.last_interaction_type,
    m.current_funnel_stage,
    m.current_fail_reason,
    md5(jsonb_build_array(
        m.membership_end_date, m.contract_end_month, m.client_id, m.access_club_id,
        m.next_contract_id, m.next_contract_code, m.renewal_activation_date,
        m.next_contract_start_date, m.next_contract_term_days, m.renewal_type,
        m.renewed_by_month_close_flag, m.renewed_current_flag,
        m.renewal_lead_lag_days, m.return_days, m.return_bucket,
        m.current_rating, m.current_tenure, m.last_interaction_at,
        m.last_interaction_type, m.current_funnel_stage, m.current_fail_reason
    )::text) AS state_hash
FROM mart.renewal_management_contract AS m;
