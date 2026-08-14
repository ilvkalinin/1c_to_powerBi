-- APPLIED 2026-08-14 after separate explicit DDL approval.
-- Target was absent on VM-2, PostgreSQL 18.3, before execution.
BEGIN;

CREATE TABLE mart.lesson_room_slot_5m (
    source_kind                 text        NOT NULL,
    source_lesson_id            text        NOT NULL,
    created_at                  timestamp   NOT NULL,
    lesson_start_at             timestamp   NOT NULL,
    lesson_end_at               timestamp   NOT NULL,
    slot_start_at               timestamp   NOT NULL,
    club_id                     text        NOT NULL,
    room_id                     text,
    employee_id                 text,
    service_id                  text,
    activity_id                 text,
    training_format_id          text,
    payment_class_current       text        NOT NULL,
    schedule_entry_timeliness   text        NOT NULL,
    is_cancelled_current        boolean,
    occupied_slot_count         smallint    NOT NULL,
    CONSTRAINT lesson_room_slot_5m_pk PRIMARY KEY (source_kind, source_lesson_id, slot_start_at),
    CONSTRAINT lesson_room_slot_5m_source_kind_ck CHECK (source_kind IN ('group_lesson', 'prebooking')),
    CONSTRAINT lesson_room_slot_5m_interval_ck CHECK (lesson_end_at > lesson_start_at),
    CONSTRAINT lesson_room_slot_5m_slot_position_ck CHECK (
        slot_start_at >= lesson_start_at
        AND slot_start_at < lesson_end_at
        AND mod(extract(epoch FROM slot_start_at - lesson_start_at)::bigint, 300) = 0
    ),
    CONSTRAINT lesson_room_slot_5m_payment_ck CHECK (payment_class_current IN ('club_time', 'paid', 'reserve')),
    CONSTRAINT lesson_room_slot_5m_timeliness_ck CHECK (schedule_entry_timeliness IN ('after', 'before_or_at_end')),
    CONSTRAINT lesson_room_slot_5m_cancelled_ck CHECK (
        (source_kind = 'group_lesson' AND is_cancelled_current IS NULL)
        OR (source_kind = 'prebooking' AND is_cancelled_current IS FALSE)
    ),
    CONSTRAINT lesson_room_slot_5m_occupied_ck CHECK (occupied_slot_count = 1)
);

COMMENT ON TABLE mart.lesson_room_slot_5m IS
    'Занятие × 5-минутный слот для занятости залов; BR-021 округляет положительный неполный интервал вверх.';
COMMIT;

-- Rollback before COMMIT: ROLLBACK. Post-commit rollback is a separate
-- approved change and is deliberately not automated.
