-- Read-only reconciliation for mart.ip_training_daily.
-- Run the source control in
-- docs/source_metadata/validation_sql/ip_training_2026-08-11.sql inside one
-- REPEATABLE READ, READ ONLY VM-1 snapshot. Its GRAIN row is the source
-- expectation: value_1 = source rows, value_2 = target-grain rows,
-- value_3 = SUM(training_count), value_4 = NULL components.
-- Run the target controls below in a VM-2 read-only transaction with the same
-- BR-003 bounds. Tolerance is exactly zero for every discrepancy.
--
-- Initial-load snapshot (2026-08-14): source rows = 142639,
-- target-grain rows = 141327, SUM(training_count) = 142639.

-- IP-REC-001 / IP-REC-002: target volume, additivity, logical key and contract.
SELECT
    count(*)::bigint AS target_grain_rows,
    coalesce(sum(training_count), 0)::bigint AS training_count_sum,
    count(*) - count(DISTINCT (training_date, club_id, employee_id, client_key, service_id))
        AS duplicate_keys,
    count(*) FILTER (
        WHERE training_date IS NULL OR club_id IS NULL OR employee_id IS NULL
           OR employee_name IS NULL OR client_key IS NULL OR client_code IS NULL
           OR service_id IS NULL OR service_name IS NULL OR training_count IS NULL
           OR training_count <= 0 OR client_key <> client_code
    ) AS contract_violations
FROM mart.ip_training_daily;

-- IP-REC-003: the bounded rebuild must remove every row outside BR-003.
-- The runner binds $1 = horizon_start and $2 = horizon_end.
SELECT count(*)::bigint AS rows_outside_horizon
FROM mart.ip_training_daily
WHERE training_date < $1::date OR training_date >= $2::date;
