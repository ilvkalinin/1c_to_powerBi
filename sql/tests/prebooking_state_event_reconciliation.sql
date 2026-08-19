-- Read-only reconciliation: mart.prebooking_state_event.
-- Initial-load expected values were independently captured from
-- prebooking_state_event_source_controls.sql in the loader's REPEATABLE READ
-- source snapshot on 2026-08-14 before target COPY:
-- rows=2389981, booking_delta=1686747, PZ=575206, GZ=1814775, arrived=133284.
-- The runner binds $1 = BR-003 horizon_start and $2 = horizon_end.

-- PB-REC-001 — source snapshot controls versus persisted mart controls.
WITH expected AS (
    SELECT 2389981::bigint AS rows, 1686747::bigint AS booking_delta,
           575206::bigint AS pz_rows, 1814775::bigint AS gz_rows,
           133284::bigint AS arrived_rows
), actual AS (
    SELECT count(*)::bigint AS rows, coalesce(sum(booking_delta), 0)::bigint AS booking_delta,
           count(*) FILTER (WHERE booking_kind = 'PZ')::bigint AS pz_rows,
           count(*) FILTER (WHERE booking_kind = 'GZ')::bigint AS gz_rows,
           count(*) FILTER (WHERE state_order = 4)::bigint AS arrived_rows
    FROM mart.prebooking_state_event
)
SELECT e.*, a.*, (a.rows = e.rows AND a.booking_delta = e.booking_delta
       AND a.pz_rows = e.pz_rows AND a.gz_rows = e.gz_rows
       AND a.arrived_rows = e.arrived_rows) AS passed
FROM expected e CROSS JOIN actual a;

-- PB-REC-002 — physical key and BR-018 PZ multiplicity.
SELECT count(*) FILTER (WHERE booking_kind = 'PZ')::bigint AS pz_physical_rows,
       count(DISTINCT (recorder_tref, recorder_id, source_line_no))
           FILTER (WHERE booking_kind = 'PZ')::bigint AS pz_state_events,
       count(*) FILTER (WHERE booking_kind = 'PZ')
         - count(DISTINCT (recorder_tref, recorder_id, source_line_no))
           FILTER (WHERE booking_kind = 'PZ') AS preserved_vt4352_excess,
       (SELECT count(*) FROM (
           SELECT 1 FROM mart.prebooking_state_event
           GROUP BY booking_kind, recorder_tref, recorder_id, source_line_no,
                    legacy_settlement_line_no
           HAVING count(*) > 1
       ) duplicates) AS duplicate_key_groups
FROM mart.prebooking_state_event;

-- PB-REC-003 — BR-003 horizon, required values, and state-to-delta contract.
SELECT count(*) FILTER (WHERE lesson_start_at < $1::date
                              OR lesson_start_at >= $2::date) AS out_of_horizon_rows,
       count(*) FILTER (WHERE state_event_at IS NULL OR booking_kind IS NULL
          OR recorder_tref IS NULL OR recorder_id IS NULL OR source_line_no IS NULL
          OR booking_document_id IS NULL OR lesson_start_at IS NULL OR lesson_end_at IS NULL
          OR club_id IS NULL OR employee_id IS NULL OR service_id IS NULL
          OR client_key IS NULL OR client_name IS NULL OR state_order IS NULL
          OR event_category IS NULL OR booking_delta IS NULL OR is_paid_booking IS NULL) AS required_null_rows,
       count(*) FILTER (WHERE (state_order = 1 AND booking_delta <> 1)
          OR (state_order IN (2, 3) AND booking_delta <> -1)
          OR (state_order = 4 AND booking_delta <> 0)) AS invalid_delta_rows,
       min(lesson_start_at)::date AS min_lesson_date,
       max(lesson_start_at)::date AS max_lesson_date
FROM mart.prebooking_state_event;

-- PB-REC-004 — branch/status values retained for Power BI measures.
SELECT booking_kind, state_order, count(*)::bigint AS rows,
       sum(booking_delta)::bigint AS booking_delta
FROM mart.prebooking_state_event
GROUP BY booking_kind, state_order
ORDER BY booking_kind, state_order;
