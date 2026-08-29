-- RMO-R01: latest nonremoved state matches the independently counted parent mart.
WITH latest AS (
    SELECT DISTINCT ON (expiring_contract_id) *
    FROM mart.renewal_management_contract_observation
    ORDER BY expiring_contract_id, observed_at DESC
)
SELECT
    $1::bigint AS expected_rows,
    $2::bigint AS expected_distinct_contracts,
    (SELECT count(*) FROM latest WHERE observation_kind <> 'REMOVED')::bigint AS actual_latest_rows,
    (SELECT count(DISTINCT expiring_contract_id) FROM latest WHERE observation_kind <> 'REMOVED')::bigint AS actual_latest_distinct_contracts,
    ($1::bigint = (SELECT count(*) FROM latest WHERE observation_kind <> 'REMOVED')
     AND $2::bigint = (SELECT count(DISTINCT expiring_contract_id) FROM latest WHERE observation_kind <> 'REMOVED')) AS passed;

-- RMO-R02: physical/logical key and mandatory current-state fields. Expected all 0.
SELECT
    (count(*) - count(DISTINCT (expiring_contract_id, observed_at)))::bigint AS duplicate_keys,
    count(*) FILTER (WHERE state_hash !~ '^[0-9a-f]{32}$')::bigint AS invalid_hashes,
    count(*) FILTER (WHERE observation_kind <> 'REMOVED' AND (
        membership_end_date IS NULL OR contract_end_month IS NULL OR client_id IS NULL
        OR access_club_id IS NULL OR renewal_type IS NULL
        OR renewed_by_month_close_flag IS NULL OR renewed_current_flag IS NULL
    ))::bigint AS invalid_current_state_rows
FROM mart.renewal_management_contract_observation;

-- RMO-R03: dates, kinds and no future observation. Expected all 0.
SELECT
    count(*) FILTER (WHERE observation_kind NOT IN ('BASELINE', 'CHANGED', 'REMOVED'))::bigint AS invalid_kind_rows,
    count(*) FILTER (WHERE observation_kind <> 'REMOVED' AND contract_end_month <> date_trunc('month', membership_end_date)::date)::bigint AS invalid_end_month_rows,
    count(*) FILTER (WHERE observed_at > clock_timestamp() + interval '1 minute')::bigint AS future_observation_rows
FROM mart.renewal_management_contract_observation;

-- RMO-R04: the latest state is exactly the current parent projection; tombstones
-- are allowed only when the parent no longer contains that contract. Expected all 0.
WITH current_state AS (
    SELECT m.expiring_contract_id,
           md5(jsonb_build_array(
               m.membership_end_date, m.contract_end_month, m.client_id, m.access_club_id,
               m.next_contract_id, m.next_contract_code, m.renewal_activation_date,
               m.next_contract_start_date, m.next_contract_term_days, m.renewal_type,
               m.renewed_by_month_close_flag, m.renewed_current_flag,
               m.renewal_lead_lag_days, m.return_days, m.return_bucket,
               m.current_rating, m.current_tenure, m.last_interaction_at,
               m.last_interaction_type, m.current_funnel_stage, m.current_fail_reason
           )::text) AS state_hash
    FROM mart.renewal_management_contract AS m
), latest AS (
    SELECT DISTINCT ON (expiring_contract_id) *
    FROM mart.renewal_management_contract_observation
    ORDER BY expiring_contract_id, observed_at DESC
)
SELECT
    count(*) FILTER (WHERE c.expiring_contract_id IS NOT NULL AND (l.expiring_contract_id IS NULL OR l.observation_kind = 'REMOVED' OR l.state_hash IS DISTINCT FROM c.state_hash))::bigint AS current_without_matching_latest_state,
    count(*) FILTER (WHERE c.expiring_contract_id IS NULL AND l.observation_kind <> 'REMOVED')::bigint AS missing_tombstone_rows,
    count(*) FILTER (WHERE c.expiring_contract_id IS NOT NULL AND l.observation_kind = 'REMOVED')::bigint AS invalid_live_tombstone_rows
FROM current_state AS c
FULL JOIN latest AS l ON l.expiring_contract_id = c.expiring_contract_id;

-- RMO-R05: parent date horizon and target access boundary. Expected all 0.
SELECT
    count(*) FILTER (WHERE observation_kind <> 'REMOVED' AND (membership_end_date < $3::date OR membership_end_date > $4::date))::bigint AS out_of_parent_horizon_rows,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
     WHERE n.nspname = 'mart'
       AND c.relname = 'renewal_management_contract_observation'
       AND a.grantee = 0 AND a.privilege_type = 'SELECT')::bigint AS public_select_grants
FROM mart.renewal_management_contract_observation;
