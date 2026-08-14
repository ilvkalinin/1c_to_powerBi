-- APPLIED 2026-08-14 after separate explicit user approval.
-- Execute only after separate explicit DDL approval; initial load requires its
-- own separate DML approval.

BEGIN;

CREATE TABLE mart.prebooking_state_event (
    state_event_at              timestamp       NOT NULL,
    booking_kind                text            NOT NULL,
    recorder_tref               text            NOT NULL,
    recorder_id                 text            NOT NULL,
    source_line_no              integer         NOT NULL,
    legacy_settlement_line_no   integer,
    booking_document_id         text            NOT NULL,
    lesson_start_at             timestamp       NOT NULL,
    lesson_end_at               timestamp       NOT NULL,
    club_id                     text            NOT NULL,
    activity_id                 text,
    employee_id                 text            NOT NULL,
    service_id                  text            NOT NULL,
    client_key                  text            NOT NULL,
    client_code                 text,
    client_name                 text            NOT NULL,
    state_order                 smallint        NOT NULL,
    event_category              text            NOT NULL,
    booking_delta               smallint        NOT NULL,
    cancelled_before_lesson     boolean,
    is_paid_booking             boolean         NOT NULL,

    CONSTRAINT prebooking_state_event_uk
        UNIQUE NULLS NOT DISTINCT (
            booking_kind, recorder_tref, recorder_id, source_line_no,
            legacy_settlement_line_no
        )
);

COMMENT ON TABLE mart.prebooking_state_event IS
    'События предзаписи; ПЗ сохраняет legacy-кратность по строкам взаиморасчётов.';

COMMIT;

-- Rollback before COMMIT: ROLLBACK. Post-commit rollback is a separate
-- approved change and is deliberately not automated.
