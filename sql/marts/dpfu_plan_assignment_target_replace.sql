-- REVIEW ONLY. Execute only through the approved loader after separate DML
-- approval. It atomically replaces mart.dpfu_plan_assignment for one BR-003
-- source snapshot; no raw 1C object is copied to VM-2.

BEGIN;

SELECT pg_advisory_xact_lock(hashtext('mart.dpfu_plan_assignment:refresh'));

CREATE TEMP TABLE _dpfu_plan_assignment_stage (
    LIKE mart.dpfu_plan_assignment INCLUDING DEFAULTS
) ON COMMIT DROP;

CREATE TEMP TABLE _dpfu_plan_assignment_expected (
    source_rows          bigint        NOT NULL,
    planned_revenue      numeric(18,2) NOT NULL,
    negative_revenue_rows bigint       NOT NULL,
    zero_revenue_rows    bigint        NOT NULL
) ON COMMIT DROP;

-- Runner actions, not executable SQL literals:
-- COPY _dpfu_plan_assignment_stage (
--   plan_date, club_id, activity_id, employee_id, planned_client_key,
--   planned_client_code, plan_line_discriminator, planned_revenue
-- ) FROM STDIN;
-- INSERT INTO _dpfu_plan_assignment_expected VALUES (...source controls...);

DO $$
BEGIN
    IF (SELECT count(*) FROM _dpfu_plan_assignment_expected) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one source-control row';
    END IF;

    IF EXISTS (
        SELECT 1 FROM _dpfu_plan_assignment_stage
        GROUP BY plan_date, club_id, activity_id, employee_id,
                 planned_client_key, plan_line_discriminator
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate target logical key in staging';
    END IF;

    IF EXISTS (
        SELECT 1 FROM _dpfu_plan_assignment_stage
        WHERE plan_date IS NULL OR club_id IS NULL OR activity_id IS NULL
           OR employee_id IS NULL OR planned_client_key IS NULL
           OR planned_client_code IS NULL OR plan_line_discriminator IS NULL
           OR planned_revenue IS NULL
    ) THEN
        RAISE EXCEPTION 'Fact-contract violation in staging';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _dpfu_plan_assignment_expected e
        CROSS JOIN (
            SELECT count(*)::bigint AS source_rows,
                   coalesce(sum(planned_revenue), 0)::numeric(18,2) AS planned_revenue,
                   count(*) FILTER (WHERE planned_revenue < 0)::bigint AS negative_revenue_rows,
                   count(*) FILTER (WHERE planned_revenue = 0)::bigint AS zero_revenue_rows
            FROM _dpfu_plan_assignment_stage
        ) s
        WHERE e.source_rows <> s.source_rows
           OR e.planned_revenue <> s.planned_revenue
           OR e.negative_revenue_rows <> s.negative_revenue_rows
           OR e.zero_revenue_rows <> s.zero_revenue_rows
    ) THEN
        RAISE EXCEPTION 'Stage controls differ from the source snapshot';
    END IF;
END $$;

DELETE FROM mart.dpfu_plan_assignment;

INSERT INTO mart.dpfu_plan_assignment (
    plan_date, club_id, activity_id, employee_id, planned_client_key,
    planned_client_code, plan_line_discriminator, planned_revenue
)
SELECT plan_date, club_id, activity_id, employee_id, planned_client_key,
       planned_client_code, plan_line_discriminator, planned_revenue
FROM _dpfu_plan_assignment_stage;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM _dpfu_plan_assignment_expected e
        CROSS JOIN (
            SELECT count(*)::bigint AS source_rows,
                   coalesce(sum(planned_revenue), 0)::numeric(18,2) AS planned_revenue,
                   count(*) FILTER (WHERE planned_revenue < 0)::bigint AS negative_revenue_rows,
                   count(*) FILTER (WHERE planned_revenue = 0)::bigint AS zero_revenue_rows
            FROM mart.dpfu_plan_assignment
        ) t
        WHERE e.source_rows <> t.source_rows
           OR e.planned_revenue <> t.planned_revenue
           OR e.negative_revenue_rows <> t.negative_revenue_rows
           OR e.zero_revenue_rows <> t.zero_revenue_rows
    ) THEN
        RAISE EXCEPTION 'Persistent fact controls differ from the source snapshot';
    END IF;
END $$;

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Post-commit rollback is a separate approved change; do not automate deletion
-- of the persistent fact.
