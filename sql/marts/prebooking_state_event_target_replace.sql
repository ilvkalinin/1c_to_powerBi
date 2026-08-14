-- REVIEW ONLY. Execute only through the approved loader after separate DML
-- approval. It atomically replaces mart.prebooking_state_event for one BR-003
-- source snapshot; no raw 1C object is copied to VM-2.

BEGIN;
SELECT pg_advisory_xact_lock(hashtext('mart.prebooking_state_event:refresh'));

CREATE TEMP TABLE _prebooking_state_event_stage (
    LIKE mart.prebooking_state_event INCLUDING DEFAULTS
) ON COMMIT DROP;

CREATE TEMP TABLE _prebooking_state_event_expected (
    target_rows bigint NOT NULL,
    booking_delta bigint NOT NULL,
    pz_rows bigint NOT NULL,
    gz_rows bigint NOT NULL,
    arrived_rows bigint NOT NULL
) ON COMMIT DROP;

-- Runner actions, not executable SQL literals:
-- COPY _prebooking_state_event_stage (all explicit contract columns) FROM STDIN;
-- INSERT INTO _prebooking_state_event_expected VALUES (...source controls...);

DO $$
BEGIN
    IF (SELECT count(*) FROM _prebooking_state_event_expected) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one source-control row';
    END IF;
    IF EXISTS (
        SELECT 1 FROM _prebooking_state_event_stage
        GROUP BY booking_kind, recorder_tref, recorder_id, source_line_no,
                 legacy_settlement_line_no
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate legacy logical key in staging';
    END IF;
    IF EXISTS (
        SELECT 1 FROM _prebooking_state_event_stage
        WHERE state_event_at IS NULL OR booking_kind IS NULL OR recorder_tref IS NULL
           OR recorder_id IS NULL OR source_line_no IS NULL OR booking_document_id IS NULL
           OR lesson_start_at IS NULL OR lesson_end_at IS NULL OR club_id IS NULL
           OR employee_id IS NULL OR service_id IS NULL OR client_key IS NULL
           OR client_name IS NULL OR state_order IS NULL OR event_category IS NULL
           OR booking_delta IS NULL OR is_paid_booking IS NULL
    ) THEN
        RAISE EXCEPTION 'Fact-contract violation in staging';
    END IF;
    IF EXISTS (
        SELECT 1 FROM _prebooking_state_event_expected e CROSS JOIN (
            SELECT count(*)::bigint AS target_rows,
                   coalesce(sum(booking_delta),0)::bigint AS booking_delta,
                   count(*) FILTER (WHERE booking_kind = 'PZ')::bigint AS pz_rows,
                   count(*) FILTER (WHERE booking_kind = 'GZ')::bigint AS gz_rows,
                   count(*) FILTER (WHERE state_order = 4)::bigint AS arrived_rows
            FROM _prebooking_state_event_stage
        ) s
        WHERE e.target_rows <> s.target_rows OR e.booking_delta <> s.booking_delta
           OR e.pz_rows <> s.pz_rows OR e.gz_rows <> s.gz_rows
           OR e.arrived_rows <> s.arrived_rows
    ) THEN
        RAISE EXCEPTION 'Stage controls differ from the source snapshot';
    END IF;
END $$;

DELETE FROM mart.prebooking_state_event;
INSERT INTO mart.prebooking_state_event (
    state_event_at, booking_kind, recorder_tref, recorder_id, source_line_no,
    legacy_settlement_line_no, booking_document_id, lesson_start_at,
    lesson_end_at, club_id, activity_id, employee_id, service_id, client_key,
    client_code, client_name, state_order, event_category, booking_delta,
    cancelled_before_lesson, is_paid_booking
)
SELECT state_event_at, booking_kind, recorder_tref, recorder_id, source_line_no,
       legacy_settlement_line_no, booking_document_id, lesson_start_at,
       lesson_end_at, club_id, activity_id, employee_id, service_id, client_key,
       client_code, client_name, state_order, event_category, booking_delta,
       cancelled_before_lesson, is_paid_booking
FROM _prebooking_state_event_stage;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM _prebooking_state_event_expected e CROSS JOIN (
            SELECT count(*)::bigint AS target_rows,
                   coalesce(sum(booking_delta),0)::bigint AS booking_delta,
                   count(*) FILTER (WHERE booking_kind = 'PZ')::bigint AS pz_rows,
                   count(*) FILTER (WHERE booking_kind = 'GZ')::bigint AS gz_rows,
                   count(*) FILTER (WHERE state_order = 4)::bigint AS arrived_rows
            FROM mart.prebooking_state_event
        ) t
        WHERE e.target_rows <> t.target_rows OR e.booking_delta <> t.booking_delta
           OR e.pz_rows <> t.pz_rows OR e.gz_rows <> t.gz_rows
           OR e.arrived_rows <> t.arrived_rows
    ) THEN
        RAISE EXCEPTION 'Persistent fact controls differ from the source snapshot';
    END IF;
END $$;
COMMIT;

-- Rollback before COMMIT: ROLLBACK. Post-commit rollback is a separate
-- approved change and is deliberately not automated.
