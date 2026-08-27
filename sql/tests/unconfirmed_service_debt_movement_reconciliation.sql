-- Bound by the approved loader with: expected rows, keys, signed amount,
-- min/max event timestamp, then BR-003 horizon start/end. No values are
-- derived from the extract path under test.
WITH expected AS (
    SELECT %s::bigint AS rows, %s::bigint AS keys, %s::numeric(20,2) AS amount_sum,
           %s::timestamp AS min_event_at, %s::timestamp AS max_event_at
), actual AS (
    SELECT count(*)::bigint AS rows,
           count(DISTINCT (debt_event_at, recorder_type, recorder_id, recorder_line_no))::bigint AS keys,
           coalesce(sum(amount_delta), 0)::numeric(20,2) AS amount_sum,
           min(debt_event_at) AS min_event_at, max(debt_event_at) AS max_event_at
    FROM mart.unconfirmed_service_debt_movement
), duplicate_key AS (
    SELECT count(*)::bigint AS rows
    FROM (
        SELECT 1
        FROM mart.unconfirmed_service_debt_movement
        GROUP BY debt_event_at, recorder_type, recorder_id, recorder_line_no
        HAVING count(*) > 1
    ) d
), contract AS (
    SELECT count(*)::bigint AS invalid_rows
    FROM mart.unconfirmed_service_debt_movement
    WHERE debt_event_at < %s::timestamp OR debt_event_at >= %s::timestamp
       OR debt_event_at IS NULL OR recorder_type IS NULL OR recorder_id IS NULL
       OR recorder_line_no IS NULL OR record_kind NOT IN (0, 1) OR client_key IS NULL
       OR club_id IS NULL OR prebooking_id IS NULL OR service_id IS NULL
       OR employee_id IS NULL OR service_start_at IS NULL OR service_end_at IS NULL
       OR quantity_delta IS NULL OR amount_delta IS NULL
)
SELECT control_id, expected_value, actual_value, actual_value - expected_value AS deviation,
       CASE WHEN actual_value = expected_value THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT 'VD-REC-001_ROWS'::text AS control_id, e.rows::numeric AS expected_value,
           a.rows::numeric AS actual_value FROM expected e CROSS JOIN actual a
    UNION ALL
    SELECT 'VD-REC-002_KEYS', e.keys::numeric, a.keys::numeric
    FROM expected e CROSS JOIN actual a
    UNION ALL
    SELECT 'VD-REC-003_AMOUNT', e.amount_sum, a.amount_sum
    FROM expected e CROSS JOIN actual a
    UNION ALL
    SELECT 'VD-REC-004_MIN_EVENT', extract(epoch FROM e.min_event_at), extract(epoch FROM a.min_event_at)
    FROM expected e CROSS JOIN actual a
    UNION ALL
    SELECT 'VD-REC-005_MAX_EVENT', extract(epoch FROM e.max_event_at), extract(epoch FROM a.max_event_at)
    FROM expected e CROSS JOIN actual a
    UNION ALL
    SELECT 'VD-REC-006_DUPLICATE_KEYS', 0::numeric, d.rows::numeric
    FROM duplicate_key d
    UNION ALL
    SELECT 'VD-REC-007_HORIZON_AND_REQUIRED', 0::numeric, c.invalid_rows::numeric
    FROM contract c
) checks
ORDER BY control_id;
