-- Read-only reconciliation for mart.ip_revenue_daily.
-- Run the independent VM-1 source control in
-- docs/source_metadata/validation_sql/ip_revenue_2026-08-14.sql inside one
-- REPEATABLE READ, READ ONLY snapshot. Compare its target_grain_rows,
-- grouped_revenue, null_club_target_rows and zero_revenue_target_rows with
-- IP-REC-001 below. Tolerance is exactly zero.
--
-- Initial-load controls (2026-08-14, BR-003 2025-01-01..2027-01-01):
-- source movements = 178022; target-grain rows = 47151;
-- revenue = 268944858.22; null-club rows = 14321; zero groups = 92.

-- IP-REC-001 / IP-REC-002: volume, additivity, logical key and contract.
SELECT
    count(*)::bigint AS target_grain_rows,
    coalesce(sum(revenue_amount), 0)::numeric(18, 2) AS revenue_amount,
    (
        SELECT count(*)::bigint
        FROM (
            SELECT 1
            FROM mart.ip_revenue_daily
            GROUP BY revenue_date, club_id, service_id
            HAVING count(*) > 1
        ) duplicate_key
    ) AS duplicate_keys,
    count(*) FILTER (
        WHERE revenue_date IS NULL OR service_id IS NULL OR service_name IS NULL
           OR revenue_amount IS NULL
    )::bigint AS contract_violations,
    count(*) FILTER (WHERE club_id IS NULL)::bigint AS null_club_target_rows,
    count(*) FILTER (WHERE revenue_amount = 0)::bigint AS zero_revenue_target_rows
FROM mart.ip_revenue_daily;

-- IP-REC-003: bounded rebuild must remove every row outside BR-003.
-- The runner binds $1 = horizon_start and $2 = horizon_end.
SELECT count(*)::bigint AS rows_outside_horizon
FROM mart.ip_revenue_daily
WHERE revenue_date < $1::date OR revenue_date >= $2::date;
