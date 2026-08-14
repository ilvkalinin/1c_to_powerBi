-- REVIEW ONLY. Execute only through the approved loader after separate DML
-- approval. It atomically replaces mart.ip_revenue_daily for one BR-003 source
-- snapshot; no raw 1C object is copied to VM-2.

BEGIN;

SELECT pg_advisory_xact_lock(hashtext('mart.ip_revenue_daily:refresh'));

CREATE TEMP TABLE _ip_revenue_daily_stage (
    LIKE mart.ip_revenue_daily INCLUDING DEFAULTS
) ON COMMIT DROP;

CREATE TEMP TABLE _ip_revenue_daily_expected (
    source_movement_rows    bigint        NOT NULL,
    target_grain_rows       bigint        NOT NULL,
    revenue_amount          numeric(18,2) NOT NULL,
    null_club_target_rows   bigint        NOT NULL,
    zero_revenue_target_rows bigint       NOT NULL
) ON COMMIT DROP;

-- Runner actions, not executable SQL literals:
-- COPY _ip_revenue_daily_stage (
--     revenue_date, club_id, service_id, service_name, revenue_amount
-- ) FROM STDIN;
-- INSERT INTO _ip_revenue_daily_expected VALUES (...source snapshot controls...);

DO $$
BEGIN
    IF (SELECT count(*) FROM _ip_revenue_daily_expected) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one source-control row';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ip_revenue_daily_stage
        GROUP BY revenue_date, club_id, service_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate target logical key in staging';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ip_revenue_daily_stage
        WHERE revenue_date IS NULL OR service_id IS NULL OR service_name IS NULL
           OR revenue_amount IS NULL
    ) THEN
        RAISE EXCEPTION 'Fact-contract violation in staging';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ip_revenue_daily_expected e
        CROSS JOIN (
            SELECT count(*)::bigint AS target_grain_rows,
                   coalesce(sum(revenue_amount), 0)::numeric(18, 2) AS revenue_amount,
                   count(*) FILTER (WHERE club_id IS NULL)::bigint AS null_club_target_rows,
                   count(*) FILTER (WHERE revenue_amount = 0)::bigint AS zero_revenue_target_rows
            FROM _ip_revenue_daily_stage
        ) s
        WHERE e.target_grain_rows <> s.target_grain_rows
           OR e.revenue_amount <> s.revenue_amount
           OR e.null_club_target_rows <> s.null_club_target_rows
           OR e.zero_revenue_target_rows <> s.zero_revenue_target_rows
    ) THEN
        RAISE EXCEPTION 'Stage controls differ from the source snapshot';
    END IF;
END $$;

DELETE FROM mart.ip_revenue_daily;

INSERT INTO mart.ip_revenue_daily (
    revenue_date, club_id, service_id, service_name, revenue_amount
)
SELECT revenue_date, club_id, service_id, service_name, revenue_amount
FROM _ip_revenue_daily_stage;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM _ip_revenue_daily_expected e
        CROSS JOIN (
            SELECT count(*)::bigint AS target_grain_rows,
                   coalesce(sum(revenue_amount), 0)::numeric(18, 2) AS revenue_amount,
                   count(*) FILTER (WHERE club_id IS NULL)::bigint AS null_club_target_rows,
                   count(*) FILTER (WHERE revenue_amount = 0)::bigint AS zero_revenue_target_rows
            FROM mart.ip_revenue_daily
        ) t
        WHERE e.target_grain_rows <> t.target_grain_rows
           OR e.revenue_amount <> t.revenue_amount
           OR e.null_club_target_rows <> t.null_club_target_rows
           OR e.zero_revenue_target_rows <> t.zero_revenue_target_rows
    ) THEN
        RAISE EXCEPTION 'Persistent fact controls differ from the source snapshot';
    END IF;
END $$;

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Post-commit rollback is a separate approved change; do not automate deletion
-- of the persistent fact.
