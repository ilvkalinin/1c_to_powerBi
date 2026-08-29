-- Independent parent-mart controls; no state-hash formula is repeated here.
SELECT
    count(*)::bigint AS expected_current_rows,
    count(DISTINCT expiring_contract_id)::bigint AS expected_distinct_contracts,
    min(membership_end_date) AS expected_min_end_date,
    max(membership_end_date) AS expected_max_end_date,
    count(*) FILTER (
        WHERE expiring_contract_id IS NULL
           OR membership_end_date IS NULL
           OR contract_end_month IS NULL
           OR client_id IS NULL
           OR access_club_id IS NULL
           OR renewal_type IS NULL
           OR renewed_by_month_close_flag IS NULL
           OR renewed_current_flag IS NULL
    )::bigint AS invalid_parent_rows
FROM mart.renewal_management_contract;
