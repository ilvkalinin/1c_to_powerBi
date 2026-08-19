-- Read-only acceptance controls for mart.administrator_card_gymmy_daily.
-- The loader captures the independent VM-1 source totals in the same
-- REPEATABLE READ snapshot that feeds the target. Compare the first query to
-- those captured totals; tolerance is exactly zero.
-- Initial-load snapshot 2026-08-19, BR-003 [2025-01-01, 2027-01-01):
--   Вход = 107583; Выход = 86694.

-- AC-REC-001: source-to-target direction totals, logical-key uniqueness and
-- required target contract. Expected: the two captured source totals,
-- duplicate_keys = 0 and contract_violations = 0.
SELECT
    direction,
    coalesce(sum(usage_count), 0)::bigint AS usage_count_sum,
    count(*)::bigint AS daily_grain_rows,
    count(*) - count(DISTINCT (event_date, club_id, direction)) AS duplicate_keys,
    count(*) FILTER (
        WHERE event_date IS NULL
           OR club_id IS NULL OR club_id = ''
           OR direction NOT IN ('Вход', 'Выход')
           OR usage_count IS NULL OR usage_count <= 0
    ) AS contract_violations
FROM mart.administrator_card_gymmy_daily
GROUP BY direction
ORDER BY direction;

-- AC-REC-002: bounded rebuild deletion control. The runner binds $1 and $2
-- to the dynamic BR-003 horizon. Expected: 0.
SELECT count(*)::bigint AS rows_outside_horizon
FROM mart.administrator_card_gymmy_daily
WHERE event_date < $1::date OR event_date >= $2::date;
