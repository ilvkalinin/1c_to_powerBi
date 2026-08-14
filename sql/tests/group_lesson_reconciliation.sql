-- Read-only reconciliation: mart.group_lesson.
-- Initial source snapshot before target DML on 2026-08-14:
-- rows=301237, capacity_sum=5951952, free_arrived_sum=1351360.

-- GL-REC-001 — source base controls versus persisted mart base controls.
WITH expected AS (
    SELECT 301237::bigint AS rows, 5951952::bigint AS capacity_sum,
           1351360::bigint AS free_arrived_sum
), actual AS (
    SELECT count(*)::bigint AS rows, coalesce(sum(capacity), 0)::bigint AS capacity_sum,
           coalesce(sum(free_program_arrived_count), 0)::bigint AS free_arrived_sum
    FROM mart.group_lesson
)
SELECT e.*, a.*, (e.rows = a.rows AND e.capacity_sum = a.capacity_sum
       AND e.free_arrived_sum = a.free_arrived_sum) AS passed
FROM expected e CROSS JOIN actual a;

-- GL-REC-002 — physical key, BR-003 horizon and contract completeness.
SELECT (SELECT count(*) FROM (
            SELECT 1 FROM mart.group_lesson GROUP BY group_lesson_id HAVING count(*) > 1
        ) duplicates) AS duplicate_key_groups,
       count(*) FILTER (WHERE lesson_start_at < DATE '2025-01-01'
                              OR lesson_start_at >= DATE '2027-01-01') AS out_of_horizon_rows,
       count(*) FILTER (WHERE group_lesson_id IS NULL OR lesson_created_at IS NULL
          OR lesson_start_at IS NULL OR lesson_end_at IS NULL OR club_id IS NULL
          OR employee_id IS NULL OR service_id IS NULL OR is_free_program IS NULL
          OR active_booking_count IS NULL OR arrived_count IS NULL
          OR free_program_arrived_count IS NULL) AS required_null_rows,
       count(*) FILTER (WHERE arrived_count < 0 OR free_program_arrived_count < 0) AS invalid_arrival_rows
FROM mart.group_lesson;

-- GL-REC-003 — independently restate shared GZ state-fact aggregation.
WITH state_per_lesson AS (
    SELECT booking_document_id AS group_lesson_id,
           coalesce(sum(booking_delta), 0)::bigint AS active_booking_count,
           nullif(count(*) FILTER (WHERE state_order = 4), 0)::bigint AS paid_arrived_count
    FROM mart.prebooking_state_event
    WHERE booking_kind = 'GZ'
    GROUP BY booking_document_id
)
SELECT count(*) FILTER (WHERE g.active_booking_count <> coalesce(s.active_booking_count, 0))
           AS active_booking_mismatches,
       count(*) FILTER (WHERE g.arrived_count <> coalesce(s.paid_arrived_count,
           g.free_program_arrived_count, 0)) AS arrived_mismatches
FROM mart.group_lesson g
LEFT JOIN state_per_lesson s USING (group_lesson_id);
