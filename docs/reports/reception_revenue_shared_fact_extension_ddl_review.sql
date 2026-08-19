-- REVIEWED AND APPLIED — 2026-08-19, package S3-RR-EXEC-001.
-- This exact migration changes the shared-fact contract and creates the views;
-- it does not load reception rows.
--
-- Product: mart.ancillary_revenue_movement + mart.v_reception_revenue.
-- Preserves all existing DPFU rows and their current business rules.

BEGIN;

SELECT pg_advisory_xact_lock(
    hashtext('mart.ancillary_revenue_movement:scope-extension')
);

-- Add the two mapped fields before assigning the existing DPFU rows.
ALTER TABLE mart.ancillary_revenue_movement
    ADD COLUMN revenue_scope text,
    ADD COLUMN reception_category_key text;

UPDATE mart.ancillary_revenue_movement
SET revenue_scope = 'dpfu'
WHERE revenue_scope IS NULL;

-- These six columns are required for DPFU but are intentionally absent from
-- the reception contract. Scope-specific constraints below preserve the DPFU
-- requirement and keep reception from carrying client data unnecessarily.
ALTER TABLE mart.ancillary_revenue_movement
    ALTER COLUMN revenue_scope SET NOT NULL,
    ALTER COLUMN client_key DROP NOT NULL,
    ALTER COLUMN client_code DROP NOT NULL,
    ALTER COLUMN activity_id DROP NOT NULL,
    ALTER COLUMN activity_name DROP NOT NULL,
    ALTER COLUMN calculation_category DROP NOT NULL,
    ALTER COLUMN age_category DROP NOT NULL;

ALTER TABLE mart.ancillary_revenue_movement
    ADD CONSTRAINT ancillary_revenue_movement_scope_ck
        CHECK (revenue_scope IN ('dpfu', 'reception')),
    ADD CONSTRAINT ancillary_revenue_movement_scope_contract_ck
        CHECK (
            (
                revenue_scope = 'dpfu'
                AND client_key IS NOT NULL
                AND client_code IS NOT NULL
                AND activity_id IS NOT NULL
                AND activity_name IS NOT NULL
                AND calculation_category IN ('Прочая услуга', 'Аренда')
                AND age_category IN ('Дети', 'Юниоры', 'Взрослые')
                AND reception_category_key IS NULL
            )
            OR (
                revenue_scope = 'reception'
                AND client_key IS NULL
                AND client_code IS NULL
                AND calculation_category IS NULL
                AND age_category IS NULL
                AND employee_id IS NOT NULL
                AND reception_category_key IN (
                    'Соляная пещера',
                    'Возмещение ущерба',
                    'Солярий',
                    'Аренда замка',
                    'Аренда полотенец и халатов',
                    'Аренда шкафчиков',
                    'Товары рецепции',
                    'Другое'
                )
            )
        );

COMMENT ON TABLE mart.ancillary_revenue_movement IS
    'Qualified DPFU and reception revenue movements; scope-specific attributes are constrained.';

-- The DPFU view prevents future reception rows from changing the existing
-- DPFU report result merely because both scopes share one physical fact.
CREATE OR REPLACE VIEW mart.v_dpfu_ancillary_revenue AS
SELECT
    source_kind,
    recorder_id,
    line_no,
    service_date,
    club_id,
    client_key,
    client_code,
    employee_id,
    employee_name,
    service_id,
    service_name,
    activity_id,
    activity_name,
    training_format_id,
    training_format_name,
    calculation_category,
    age_category,
    service_quantity,
    revenue_amount
FROM mart.ancillary_revenue_movement
WHERE revenue_scope = 'dpfu';

CREATE OR REPLACE VIEW mart.v_reception_revenue AS
SELECT
    service_date AS revenue_date,
    club_id,
    employee_id,
    service_id,
    activity_id,
    reception_category_key,
    source_kind,
    service_quantity AS sold_quantity,
    revenue_amount
FROM mart.ancillary_revenue_movement
WHERE revenue_scope = 'reception';

COMMIT;

-- Applied result: 21 columns, 7 key/check constraints, 10 physical NOT NULL
-- columns; all 504691 existing rows remain `dpfu`; both views exist; the
-- reception view is empty pending a separately approved initial-load package.
-- Any rollback is a separate approved migration; do not DROP the shared fact
-- or views automatically.
