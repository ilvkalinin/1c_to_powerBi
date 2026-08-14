-- REVIEW ONLY. Execute only through the approved loader after separate DML
-- approval. It atomically replaces mart.prebooking_state_event for one BR-003
-- source snapshot; no raw 1C object is copied to VM-2.

BEGIN;
SELECT pg_advisory_xact_lock(hashtext('mart.prebooking_state_event:refresh'));

CREATE TEMP TABLE _prebooking_state_event_expected (
    target_rows bigint NOT NULL,
    booking_delta bigint NOT NULL,
    pz_rows bigint NOT NULL,
    gz_rows bigint NOT NULL,
    arrived_rows bigint NOT NULL
) ON COMMIT DROP;

-- Runner actions, not executable SQL literals:
-- First obtain source controls from the narrow read-only control query, then
-- COPY mart.prebooking_state_event (all explicit contract columns) FROM STDIN.
-- NOT NULL and UNIQUE NULLS NOT DISTINCT enforce the contract during COPY.
-- INSERT INTO _prebooking_state_event_expected VALUES (...source controls...);

DO $$
BEGIN
    IF (SELECT count(*) FROM _prebooking_state_event_expected) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one source-control row';
    END IF;
END $$;

DELETE FROM mart.prebooking_state_event;
-- COPY mart.prebooking_state_event (...) FROM STDIN is performed by the runner.

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
