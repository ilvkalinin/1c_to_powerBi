-- S3-CBD-PKG-001 / BR-038 target migration.
-- The runner owns the transaction and advisory lock. This file must contain
-- exactly the reviewed constraint replacement below; no source object changes.
-- `Дети` is intentionally allowed at every factual age because the physical
-- aggregate has no source-type column. Extract priority and source-side
-- reconciliation prove that age 14+ `Дети` rows originate only from packages.

ALTER TABLE mart.client_base_daily
    DROP CONSTRAINT client_base_daily_age_ck;

ALTER TABLE mart.client_base_daily
    ADD CONSTRAINT client_base_daily_age_ck
    CHECK (
        (age_years IS NULL AND age_group IN ('Не указано', 'Дети'))
        OR (age_years IS NOT NULL AND age_group = 'Дети')
        OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
        OR (age_years >= 18 AND age_group = 'Взрослые')
    ) NOT VALID;

-- Rollback (manual only; execute only after BR-038 package rows are removed
-- or restored from a pre-BR-038 snapshot; it is unsafe while such rows remain):
-- ALTER TABLE mart.client_base_daily DROP CONSTRAINT client_base_daily_age_ck;
-- ALTER TABLE mart.client_base_daily ADD CONSTRAINT client_base_daily_age_ck CHECK (
--     (age_years IS NULL AND age_group = 'Не указано')
--     OR (age_years < 14 AND age_group = 'Дети')
--     OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
--     OR (age_years >= 18 AND age_group = 'Взрослые')
-- );
