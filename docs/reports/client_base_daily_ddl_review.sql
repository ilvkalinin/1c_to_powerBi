-- REVIEWED AND APPLIED 2026-08-19 after separate user approval for DDL.
-- Product: mart.client_base_daily.
-- No client IDs, PII, raw memberships or retention rows are stored here.

BEGIN;

CREATE TABLE mart.client_base_daily (
    scope_level  text    NOT NULL,
    report_date  date    NOT NULL,
    club_id      text,
    age_years    smallint,
    age_group    text    NOT NULL,
    gender       text    NOT NULL,
    client_count bigint  NOT NULL,
    CONSTRAINT client_base_daily_scope_ck
        CHECK (
            (scope_level = 'club' AND club_id IS NOT NULL)
            OR (scope_level = 'network' AND club_id IS NULL)
        ),
    CONSTRAINT client_base_daily_age_ck
        CHECK (
            (age_years IS NULL AND age_group = 'Не указано')
            OR (age_years >= 0 AND (
                (age_years < 14 AND age_group = 'Дети')
                OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
                OR (age_years >= 18 AND age_group = 'Взрослые')
            ))
        ),
    CONSTRAINT client_base_daily_gender_ck
        CHECK (gender IN ('Женский', 'Мужской', 'Не указано')),
    CONSTRAINT client_base_daily_count_ck
        CHECK (client_count > 0),
    CONSTRAINT client_base_daily_uq
        UNIQUE NULLS NOT DISTINCT (
            scope_level, report_date, club_id, age_years, age_group, gender
        )
);

COMMENT ON TABLE mart.client_base_daily IS
    'Daily aggregated client-base denominator; client and membership details remain source-side.';

COMMIT;

-- This reviewed definition is retained as the physical-schema record.
-- Post-commit rollback is a separate approved change. Do not delete the fact
-- automatically.
