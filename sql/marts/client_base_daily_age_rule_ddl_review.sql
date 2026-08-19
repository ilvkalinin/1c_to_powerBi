-- REVIEWED AND APPLIED 2026-08-19 after separate target-DDL approval.
-- Product: mart.client_base_daily.
-- Purpose: preserve the approved current client-base rule: every calculated
-- age below 14, including negative values caused by a future birth date, is
-- classified as 'Дети'. NULL retains the separate 'Не указано' category.
-- The table is confirmed empty before this migration. No source object changes.

BEGIN;

ALTER TABLE mart.client_base_daily
    DROP CONSTRAINT client_base_daily_age_ck;

ALTER TABLE mart.client_base_daily
    ADD CONSTRAINT client_base_daily_age_ck
    CHECK (
        (age_years IS NULL AND age_group = 'Не указано')
        OR (age_years < 14 AND age_group = 'Дети')
        OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
        OR (age_years >= 18 AND age_group = 'Взрослые')
    );

COMMIT;
