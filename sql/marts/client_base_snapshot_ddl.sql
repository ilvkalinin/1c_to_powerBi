-- Stage 3 product-admission reviewed DDL. The runner owns the outer
-- transaction; it never issues automatic DROP on failure.
BEGIN;

CREATE TABLE mart.client_base_snapshot (
    scope_level       text     NOT NULL,
    report_date       date     NOT NULL,
    club_id           text,
    age_years         smallint,
    age_group         text     NOT NULL,
    gender            text     NOT NULL,
    membership_tenure text     NOT NULL,
    activity_bucket   text     NOT NULL,
    client_count      bigint   NOT NULL,
    CONSTRAINT client_base_snapshot_scope_ck CHECK (
        (scope_level = 'club' AND club_id IS NOT NULL)
        OR (scope_level = 'network' AND club_id IS NULL)
    ),
    CONSTRAINT client_base_snapshot_age_ck CHECK (
        age_group = 'Дети'
        OR (age_years IS NULL AND age_group = 'Не указано')
        OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
        OR (age_years >= 18 AND age_group = 'Взрослые')
    ),
    CONSTRAINT client_base_snapshot_gender_ck CHECK (
        gender IN ('Женский', 'Мужской', 'Не указано')
    ),
    CONSTRAINT client_base_snapshot_tenure_ck CHECK (
        membership_tenure IN ('New', 'Renew', 'Ex', 'Не указано')
    ),
    CONSTRAINT client_base_snapshot_activity_ck CHECK (
        activity_bucket IN ('Не ходил', '1', '2–3', '4–7', '8+')
    ),
    CONSTRAINT client_base_snapshot_count_ck CHECK (client_count > 0),
    CONSTRAINT client_base_snapshot_uq UNIQUE NULLS NOT DISTINCT (
        scope_level, report_date, club_id, age_years, age_group, gender,
        membership_tenure, activity_bucket
    )
);

COMMENT ON TABLE mart.client_base_snapshot IS
    'Aggregated client-base snapshots; no client IDs, PII, memberships or visits are stored.';

COMMIT;
