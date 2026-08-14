-- REVIEW ONLY. Execute through scripts/load_group_lesson.py after separate DML
-- approval. Source base rows land in a transaction-local stage; GZ state
-- aggregates are read from the completed mart.prebooking_state_event fact.
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('mart.group_lesson:refresh'));

CREATE TEMP TABLE _group_lesson_source_stage (
    group_lesson_id text NOT NULL,
    lesson_created_at timestamp NOT NULL,
    lesson_start_at timestamp NOT NULL,
    lesson_end_at timestamp NOT NULL,
    club_id text NOT NULL,
    activity_id text,
    employee_id text NOT NULL,
    service_id text NOT NULL,
    capacity integer,
    is_free_program boolean NOT NULL,
    free_program_arrived_count integer NOT NULL
) ON COMMIT DROP;

-- COPY source base columns to _group_lesson_source_stage, then:
DELETE FROM mart.group_lesson;
WITH state_per_lesson AS (
    SELECT booking_document_id AS group_lesson_id,
           coalesce(sum(booking_delta), 0)::bigint AS active_booking_count,
           nullif(count(*) FILTER (WHERE state_order = 4), 0)::bigint AS paid_arrived_count
    FROM mart.prebooking_state_event
    WHERE booking_kind = 'GZ'
    GROUP BY booking_document_id
)
INSERT INTO mart.group_lesson (
    group_lesson_id, lesson_created_at, lesson_start_at, lesson_end_at,
    club_id, activity_id, employee_id, service_id, capacity, is_free_program,
    active_booking_count, arrived_count, free_program_arrived_count
)
SELECT s.group_lesson_id, s.lesson_created_at, s.lesson_start_at, s.lesson_end_at,
       s.club_id, s.activity_id, s.employee_id, s.service_id, s.capacity,
       s.is_free_program, coalesce(st.active_booking_count, 0),
       coalesce(st.paid_arrived_count, s.free_program_arrived_count, 0),
       s.free_program_arrived_count
FROM _group_lesson_source_stage s
LEFT JOIN state_per_lesson st USING (group_lesson_id);
COMMIT;
