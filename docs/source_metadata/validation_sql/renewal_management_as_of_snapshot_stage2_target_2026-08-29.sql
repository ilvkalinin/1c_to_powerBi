-- RM-ASOF-S2-001 — target-side controls. Execute only in REPEATABLE READ, READ ONLY.

-- ASOF-V01: the current mart is a valid, uniquely keyed upstream state source.
SELECT
    'ASOF-V01'::text AS control_id,
    count(*)::bigint AS current_fact_rows,
    count(DISTINCT expiring_contract_id)::bigint AS distinct_contract_ids,
    count(*) FILTER (WHERE expiring_contract_id IS NULL)::bigint AS null_contract_ids,
    (count(*) - count(DISTINCT expiring_contract_id))::bigint AS duplicate_contract_rows
FROM mart.renewal_management_contract;

-- ASOF-V02: current-state rows can be compared unambiguously by the contract key.
SELECT
    'ASOF-V02'::text AS control_id,
    count(*)::bigint AS comparison_rows,
    count(*) FILTER (WHERE renewal_type IS NULL)::bigint AS null_renewal_type_rows,
    count(*) FILTER (WHERE renewed_by_month_close_flag IS NULL)::bigint AS null_month_close_flag_rows,
    count(*) FILTER (WHERE renewed_current_flag IS NULL)::bigint AS null_current_renewal_flag_rows,
    count(*) FILTER (WHERE membership_end_date IS NULL)::bigint AS null_contract_end_rows
FROM mart.renewal_management_contract;

-- ASOF-V04: no observation table has been created during the Stage 2 validation.
SELECT
    'ASOF-V04'::text AS control_id,
    (to_regclass('mart.renewal_management_contract_observation') IS NULL) AS observation_relation_absent;
