-- Approved refresh procedure. Its first run completed 2026-08-14.
--
-- This script is the VM-2 half of one full atomic rebuild of
-- mart.ancillary_revenue_movement for the BR-003 horizon. It may be run only
-- after a separate user approval for DML. The runner must first:
--   1. calculate horizon_start/horizon_end from BR-003;
--   2. open both source extract files in one REPEATABLE READ, READ ONLY snapshot;
--   3. run the independent source controls in sql/tests/...reconciliation.sql;
--   4. stream the two extracts into _ancillary_revenue_movement_stage and insert
--      their source controls into _ancillary_revenue_movement_expected.
--
-- The runner must issue ROLLBACK when any check raises an exception. It must not
-- skip the temporary-stage checks or replace the fact with a partial source read.

BEGIN;

-- Only one refresh of this fact may replace the table at a time.
SELECT pg_advisory_xact_lock(hashtext('mart.ancillary_revenue_movement:refresh'));

CREATE TEMP TABLE _ancillary_revenue_movement_stage (
    LIKE mart.ancillary_revenue_movement INCLUDING DEFAULTS
) ON COMMIT DROP;

CREATE TEMP TABLE _ancillary_revenue_movement_expected (
    source_kind    text PRIMARY KEY,
    movement_rows  bigint NOT NULL,
    service_quantity numeric(18, 3) NOT NULL,
    revenue_amount numeric(18, 2) NOT NULL
) ON COMMIT DROP;

-- Runner action, not an executable SQL literal:
-- COPY _ancillary_revenue_movement_stage (
--     source_kind, recorder_id, line_no, service_date, club_id, client_key,
--     client_code, employee_id, employee_name, service_id, service_name,
--     activity_id, activity_name, training_format_id, training_format_name,
--     calculation_category, age_category, service_quantity, revenue_amount
-- ) FROM STDIN;
--
-- The runner sends both branch resultsets and exactly two source-control rows.

DO $$
BEGIN
    IF (SELECT count(*) FROM _ancillary_revenue_movement_expected) <> 2 THEN
        RAISE EXCEPTION 'Expected source controls for exactly two branches';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ancillary_revenue_movement_stage
        GROUP BY source_kind, recorder_id, line_no
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate movement key in staging';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ancillary_revenue_movement_stage
        WHERE source_kind IS NULL OR recorder_id IS NULL OR line_no IS NULL
           OR service_date IS NULL OR club_id IS NULL OR client_key IS NULL
           OR client_code IS NULL OR service_id IS NULL OR service_name IS NULL
           OR activity_id IS NULL OR activity_name IS NULL
           OR calculation_category IS NULL OR age_category IS NULL
           OR service_quantity IS NULL OR revenue_amount IS NULL
    ) THEN
        RAISE EXCEPTION 'Unexpected NULL in a required target column';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ancillary_revenue_movement_stage
        WHERE source_kind NOT IN ('7575', '7646')
           OR calculation_category NOT IN ('Прочая услуга', 'Аренда')
           OR age_category NOT IN ('Дети', 'Юниоры', 'Взрослые')
           OR client_key <> client_code
    ) THEN
        RAISE EXCEPTION 'Stage row does not satisfy the fact contract';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _ancillary_revenue_movement_expected e
        FULL OUTER JOIN (
            SELECT source_kind,
                   count(*)::bigint AS movement_rows,
                   sum(service_quantity)::numeric(18, 3) AS service_quantity,
                   sum(revenue_amount)::numeric(18, 2) AS revenue_amount
            FROM _ancillary_revenue_movement_stage
            GROUP BY source_kind
        ) s USING (source_kind)
        WHERE e.source_kind IS NULL OR s.source_kind IS NULL
           OR e.movement_rows <> s.movement_rows
           OR e.service_quantity <> s.service_quantity
           OR e.revenue_amount <> s.revenue_amount
    ) THEN
        RAISE EXCEPTION 'Stage controls differ from the source snapshot';
    END IF;
END $$;

-- The stage is complete and reconciled before this first persistent DML.
-- The table is dedicated to this product, so deleting it in one transaction
-- guarantees that rows outside a newly calculated BR-003 horizon do not remain.
DELETE FROM mart.ancillary_revenue_movement;

INSERT INTO mart.ancillary_revenue_movement (
    source_kind, recorder_id, line_no, service_date, club_id, client_key,
    client_code, employee_id, employee_name, service_id, service_name,
    activity_id, activity_name, training_format_id, training_format_name,
    calculation_category, age_category, service_quantity, revenue_amount
)
SELECT
    source_kind, recorder_id, line_no, service_date, club_id, client_key,
    client_code, employee_id, employee_name, service_id, service_name,
    activity_id, activity_name, training_format_id, training_format_name,
    calculation_category, age_category, service_quantity, revenue_amount
FROM _ancillary_revenue_movement_stage;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM _ancillary_revenue_movement_expected e
        FULL OUTER JOIN (
            SELECT source_kind,
                   count(*)::bigint AS movement_rows,
                   sum(service_quantity)::numeric(18, 3) AS service_quantity,
                   sum(revenue_amount)::numeric(18, 2) AS revenue_amount
            FROM mart.ancillary_revenue_movement
            GROUP BY source_kind
        ) t USING (source_kind)
        WHERE e.source_kind IS NULL OR t.source_kind IS NULL
           OR e.movement_rows <> t.movement_rows
           OR e.service_quantity <> t.service_quantity
           OR e.revenue_amount <> t.revenue_amount
    ) THEN
        RAISE EXCEPTION 'Persistent fact controls differ from the source snapshot';
    END IF;
END $$;

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Rollback after COMMIT is a separate approved change. Do not delete the fact
-- automatically; restore from the verified backup point when necessary.
