-- Read-only reconciliation: mart.lesson_room_slot_5m.
-- Initial source snapshot before target DML on 2026-08-14:
-- rows=5424234, group_slots=1968061, prebooking_slots=3456173,
-- group_lessons=187435, prebooking_lessons=384089.
-- The runner binds $1 = BR-003 horizon_start and $2 = horizon_end.

-- LS-REC-001 — snapshot controls versus the persisted target.
WITH expected AS (
    SELECT 5424234::bigint AS rows, 1968061::bigint AS group_slots,
           3456173::bigint AS prebooking_slots, 187435::bigint AS group_lessons,
           384089::bigint AS prebooking_lessons
), actual AS (
    SELECT count(*)::bigint AS rows,
           count(*) FILTER (WHERE source_kind = 'group_lesson')::bigint AS group_slots,
           count(*) FILTER (WHERE source_kind = 'prebooking')::bigint AS prebooking_slots,
           count(DISTINCT source_lesson_id) FILTER (WHERE source_kind = 'group_lesson')::bigint AS group_lessons,
           count(DISTINCT source_lesson_id) FILTER (WHERE source_kind = 'prebooking')::bigint AS prebooking_lessons
    FROM mart.lesson_room_slot_5m
)
SELECT e.*, a.*, (e.rows = a.rows AND e.group_slots = a.group_slots
       AND e.prebooking_slots = a.prebooking_slots
       AND e.group_lessons = a.group_lessons
       AND e.prebooking_lessons = a.prebooking_lessons) AS passed
FROM expected AS e CROSS JOIN actual AS a;

-- LS-REC-002 — target contract and BR-003 horizon.
SELECT count(*) FILTER (WHERE lesson_start_at < $1::date
                              OR lesson_start_at >= $2::date) AS out_of_horizon_rows,
       count(*) FILTER (WHERE source_kind IS NULL OR source_lesson_id IS NULL
          OR created_at IS NULL OR lesson_start_at IS NULL OR lesson_end_at IS NULL
          OR slot_start_at IS NULL OR club_id IS NULL OR payment_class_current IS NULL
          OR schedule_entry_timeliness IS NULL OR occupied_slot_count IS NULL) AS required_null_rows,
       count(*) FILTER (WHERE lesson_end_at <= lesson_start_at
          OR slot_start_at < lesson_start_at OR slot_start_at >= lesson_end_at
          OR mod(extract(epoch FROM slot_start_at - lesson_start_at)::bigint, 300) <> 0
          OR occupied_slot_count <> 1) AS invalid_slot_rows,
       count(*) FILTER (WHERE (source_kind = 'group_lesson' AND is_cancelled_current IS NOT NULL)
          OR (source_kind = 'prebooking' AND is_cancelled_current IS DISTINCT FROM FALSE)) AS invalid_cancelled_rows
FROM mart.lesson_room_slot_5m;

-- LS-REC-003 — every retained lesson has the exact BR-021 rounded slot count.
WITH per_lesson AS (
    SELECT source_kind, source_lesson_id,
           min(lesson_start_at) AS lesson_start_at,
           max(lesson_end_at) AS lesson_end_at,
           count(*)::bigint AS actual_slots,
           count(DISTINCT lesson_start_at) AS start_values,
           count(DISTINCT lesson_end_at) AS end_values
    FROM mart.lesson_room_slot_5m
    GROUP BY source_kind, source_lesson_id
)
SELECT count(*) FILTER (WHERE start_values <> 1 OR end_values <> 1) AS inconsistent_lesson_boundaries,
       count(*) FILTER (WHERE lesson_end_at <= lesson_start_at) AS nonpositive_retained_lessons,
       count(*) FILTER (WHERE actual_slots <> ceil(extract(epoch FROM lesson_end_at - lesson_start_at) / 300.0)::bigint)
           AS br021_slot_count_mismatches
FROM per_lesson;
