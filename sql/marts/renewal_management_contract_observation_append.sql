-- Append only new/changed current states and one tombstone for each removal.
-- The observed_at parameter is generated once by the approved psycopg runner.
WITH current_state AS MATERIALIZED (
    {{CURRENT_STATE_EXTRACT}}
),
latest_observation AS MATERIALIZED (
    SELECT DISTINCT ON (o.expiring_contract_id)
        o.*
    FROM mart.renewal_management_contract_observation AS o
    ORDER BY o.expiring_contract_id, o.observed_at DESC
),
state_delta AS (
    SELECT
        c.expiring_contract_id,
        CASE WHEN o.expiring_contract_id IS NULL THEN 'BASELINE' ELSE 'CHANGED' END AS observation_kind,
        c.state_hash,
        c.membership_end_date, c.contract_end_month, c.client_id, c.access_club_id,
        c.next_contract_id, c.next_contract_code, c.renewal_activation_date,
        c.next_contract_start_date, c.next_contract_term_days, c.renewal_type,
        c.renewed_by_month_close_flag, c.renewed_current_flag, c.renewal_lead_lag_days,
        c.return_days, c.return_bucket, c.current_rating, c.current_tenure,
        c.last_interaction_at, c.last_interaction_type, c.current_funnel_stage,
        c.current_fail_reason
    FROM current_state AS c
    LEFT JOIN latest_observation AS o ON o.expiring_contract_id = c.expiring_contract_id
    WHERE o.expiring_contract_id IS NULL
       OR o.observation_kind = 'REMOVED'
       OR o.state_hash IS DISTINCT FROM c.state_hash
),
removal_delta AS (
    SELECT
        o.expiring_contract_id, 'REMOVED'::text AS observation_kind, o.state_hash,
        o.membership_end_date, o.contract_end_month, o.client_id, o.access_club_id,
        o.next_contract_id, o.next_contract_code, o.renewal_activation_date,
        o.next_contract_start_date, o.next_contract_term_days, o.renewal_type,
        o.renewed_by_month_close_flag, o.renewed_current_flag, o.renewal_lead_lag_days,
        o.return_days, o.return_bucket, o.current_rating, o.current_tenure,
        o.last_interaction_at, o.last_interaction_type, o.current_funnel_stage,
        o.current_fail_reason
    FROM latest_observation AS o
    LEFT JOIN current_state AS c ON c.expiring_contract_id = o.expiring_contract_id
    WHERE c.expiring_contract_id IS NULL
      AND o.observation_kind <> 'REMOVED'
),
all_delta AS (
    SELECT * FROM state_delta
    UNION ALL
    SELECT * FROM removal_delta
)
INSERT INTO mart.renewal_management_contract_observation (
    expiring_contract_id, observed_at, observation_kind, state_hash,
    membership_end_date, contract_end_month, client_id, access_club_id,
    next_contract_id, next_contract_code, renewal_activation_date,
    next_contract_start_date, next_contract_term_days, renewal_type,
    renewed_by_month_close_flag, renewed_current_flag, renewal_lead_lag_days,
    return_days, return_bucket, current_rating, current_tenure, last_interaction_at,
    last_interaction_type, current_funnel_stage, current_fail_reason
)
SELECT
    d.expiring_contract_id, %s::timestamptz, d.observation_kind, d.state_hash,
    d.membership_end_date, d.contract_end_month, d.client_id, d.access_club_id,
    d.next_contract_id, d.next_contract_code, d.renewal_activation_date,
    d.next_contract_start_date, d.next_contract_term_days, d.renewal_type,
    d.renewed_by_month_close_flag, d.renewed_current_flag, d.renewal_lead_lag_days,
    d.return_days, d.return_bucket, d.current_rating, d.current_tenure,
    d.last_interaction_at, d.last_interaction_type, d.current_funnel_stage,
    d.current_fail_reason
FROM all_delta AS d
RETURNING observation_kind;
