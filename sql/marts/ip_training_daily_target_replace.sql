-- REVIEW ONLY. Execute only through the approved loader after separate DML
-- approval. It atomically replaces mart.ip_training_daily for one BR-003
-- source snapshot; no raw 1C object is copied to VM-2.

BEGIN;

SELECT pg_advisory_xact_lock(hashtext('mart.ip_training_daily:refresh'));

CREATE TEMP TABLE _ip_training_daily_stage (
    LIKE mart.ip_training_daily INCLUDING DEFAULTS
) ON COMMIT DROP;

CREATE TEMP TABLE _ip_training_daily_expected (
    source_rows       bigint NOT NULL,
    target_grain_rows bigint NOT NULL,
    training_count    bigint NOT NULL
) ON COMMIT DROP;

-- Runner action, not an executable SQL literal:
-- COPY _ip_training_daily_stage (
--     training_date, club_id, employee_id, employee_name, client_key,
--     client_code, service_id, service_name, training_count
-- ) FROM STDIN;
-- INSERT INTO _ip_training_daily_expected VALUES (...source snapshot controls...);

DO $$
BEGIN
    IF (SELECT count(*) FROM _ip_training_daily_expected) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one source-control row';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ip_training_daily_stage
        GROUP BY training_date, club_id, employee_id, client_key, service_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate target logical key in staging';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ip_training_daily_stage
        WHERE training_date IS NULL OR club_id IS NULL OR employee_id IS NULL
           OR employee_name IS NULL OR client_key IS NULL OR client_code IS NULL
           OR service_id IS NULL OR service_name IS NULL OR training_count IS NULL
           OR training_count <= 0 OR client_key <> client_code
    ) THEN
        RAISE EXCEPTION 'Fact-contract violation in staging';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ip_training_daily_expected e
        CROSS JOIN (
            SELECT count(*)::bigint AS target_grain_rows,
                   coalesce(sum(training_count), 0)::bigint AS training_count
            FROM _ip_training_daily_stage
        ) s
        WHERE e.source_rows <> e.training_count
           OR e.target_grain_rows <> s.target_grain_rows
           OR e.training_count <> s.training_count
    ) THEN
        RAISE EXCEPTION 'Stage controls differ from the source snapshot';
    END IF;
END $$;

DELETE FROM mart.ip_training_daily;

INSERT INTO mart.ip_training_daily (
    training_date, club_id, employee_id, employee_name, client_key,
    client_code, service_id, service_name, training_count
)
SELECT training_date, club_id, employee_id, employee_name, client_key,
       client_code, service_id, service_name, training_count
FROM _ip_training_daily_stage;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM _ip_training_daily_expected e
        CROSS JOIN (
            SELECT count(*)::bigint AS target_grain_rows,
                   coalesce(sum(training_count), 0)::bigint AS training_count
            FROM mart.ip_training_daily
        ) t
        WHERE e.target_grain_rows <> t.target_grain_rows
           OR e.training_count <> t.training_count
    ) THEN
        RAISE EXCEPTION 'Persistent fact controls differ from the source snapshot';
    END IF;
END $$;

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Post-commit rollback is a separate approved change; do not automate deletion
-- of the persistent fact.
