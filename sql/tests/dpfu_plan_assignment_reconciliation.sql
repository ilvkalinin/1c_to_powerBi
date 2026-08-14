-- Read-only reconciliation for mart.dpfu_plan_assignment.
-- Run the independent VM-1 source control in
-- docs/source_metadata/validation_sql/dpfu_plan_2026-08-14.sql inside one
-- REPEATABLE READ, READ ONLY snapshot. Compare source_rows and
-- planned_revenue with PLAN-REC-001. Tolerance is exactly zero.
--
-- Initial-load controls (2026-08-14, BR-003 2025-01-01..2027-01-01):
-- source rows = 528482; planned revenue = 722999695.41;
-- negative rows = 30; zero rows = 0; excess-with-discriminator = 0.

-- PLAN-REC-001 / PLAN-REC-002: volume, additivity, logical key and contract.
SELECT
    count(*)::bigint AS target_rows,
    coalesce(sum(planned_revenue), 0)::numeric(18,2) AS planned_revenue,
    (
        SELECT count(*)::bigint
        FROM (
            SELECT 1 FROM mart.dpfu_plan_assignment
            GROUP BY plan_date, club_id, activity_id, employee_id,
                     planned_client_key, plan_line_discriminator
            HAVING count(*) > 1
        ) duplicate_key
    ) AS duplicate_keys,
    count(*) FILTER (
        WHERE plan_date IS NULL OR club_id IS NULL OR activity_id IS NULL
           OR employee_id IS NULL OR planned_client_key IS NULL
           OR planned_client_code IS NULL OR plan_line_discriminator IS NULL
           OR planned_revenue IS NULL
    )::bigint AS contract_violations,
    count(*) FILTER (WHERE planned_revenue < 0)::bigint AS negative_revenue_rows,
    count(*) FILTER (WHERE planned_revenue = 0)::bigint AS zero_revenue_rows
FROM mart.dpfu_plan_assignment;

-- PLAN-REC-003: bounded rebuild must remove every row outside BR-003.
-- The runner binds $1 = horizon_start and $2 = horizon_end.
SELECT count(*)::bigint AS rows_outside_horizon
FROM mart.dpfu_plan_assignment
WHERE plan_date < $1::date OR plan_date >= $2::date;
