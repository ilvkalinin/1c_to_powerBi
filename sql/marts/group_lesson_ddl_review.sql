-- REVIEW ONLY. Execute only after separate explicit DDL approval.
BEGIN;

CREATE TABLE mart.group_lesson (
    group_lesson_id                text        NOT NULL,
    lesson_created_at              timestamp   NOT NULL,
    lesson_start_at                timestamp   NOT NULL,
    lesson_end_at                  timestamp   NOT NULL,
    club_id                        text        NOT NULL,
    activity_id                    text,
    employee_id                    text        NOT NULL,
    service_id                     text        NOT NULL,
    capacity                       integer,
    is_free_program                boolean     NOT NULL,
    active_booking_count           bigint      NOT NULL,
    arrived_count                  bigint      NOT NULL,
    free_program_arrived_count     integer     NOT NULL,
    CONSTRAINT group_lesson_pk PRIMARY KEY (group_lesson_id)
);

COMMENT ON TABLE mart.group_lesson IS
    'Одно непомеченное групповое занятие: вместимость и итоговые записи.';
COMMIT;

-- Rollback before COMMIT: ROLLBACK. Post-commit rollback is a separate
-- approved change and is deliberately not automated.
