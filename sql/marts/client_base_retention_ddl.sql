-- Stage 3 product-admission reviewed DDL. The runner owns the outer
-- transaction; it never issues automatic DROP on failure.
BEGIN;

CREATE TABLE mart.client_base_retention (
    scope_level               text     NOT NULL,
    report_date               date     NOT NULL,
    comparison_type           text     NOT NULL,
    comparison_date           date     NOT NULL,
    baseline_club_id          text,
    current_age_years         smallint,
    current_age_group         text     NOT NULL,
    current_gender            text     NOT NULL,
    current_membership_tenure text     NOT NULL,
    baseline_client_count     bigint   NOT NULL,
    retained_client_count     bigint   NOT NULL,
    CONSTRAINT client_base_retention_scope_ck CHECK (
        (scope_level = 'club' AND baseline_club_id IS NOT NULL)
        OR (scope_level = 'network' AND baseline_club_id IS NULL)
    ),
    CONSTRAINT client_base_retention_comparison_ck CHECK (
        comparison_type IN ('year_start', 'previous_year')
        AND comparison_date <= report_date
    ),
    CONSTRAINT client_base_retention_age_ck CHECK (
        current_age_group = 'Дети'
        OR (current_age_years IS NULL AND current_age_group = 'Не указано')
        OR (current_age_years BETWEEN 14 AND 17 AND current_age_group = 'Юниоры')
        OR (current_age_years >= 18 AND current_age_group = 'Взрослые')
    ),
    CONSTRAINT client_base_retention_gender_ck CHECK (
        current_gender IN ('Женский', 'Мужской', 'Не указано')
    ),
    CONSTRAINT client_base_retention_tenure_ck CHECK (
        current_membership_tenure IN ('New', 'Renew', 'Ex', 'Не указано')
    ),
    CONSTRAINT client_base_retention_counts_ck CHECK (
        baseline_client_count > 0
        AND retained_client_count >= 0
        AND retained_client_count <= baseline_client_count
    ),
    CONSTRAINT client_base_retention_uq UNIQUE NULLS NOT DISTINCT (
        scope_level, report_date, comparison_type, comparison_date,
        baseline_club_id, current_age_years, current_age_group,
        current_gender, current_membership_tenure
    )
);

COMMENT ON TABLE mart.client_base_retention IS
    'Aggregated retention cohorts; client identifiers are used only source-side.';

COMMIT;
