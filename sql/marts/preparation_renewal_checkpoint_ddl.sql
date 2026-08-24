-- REVIEWED Stage-3 DDL: mart.preparation_renewal_checkpoint.
-- Apply only through scripts/load_preparation_renewal_checkpoint.py.
-- Grain: contract × checkpoint day (7/14/21/28/30).

BEGIN;

CREATE TABLE mart.preparation_renewal_checkpoint (
    contract_id                 text     NOT NULL,
    contract_code               text     NOT NULL,
    client_id                   text     NOT NULL,
    membership_start_date       date     NOT NULL,
    membership_end_date         date     NOT NULL,
    access_club_id              text     NOT NULL,
    access_club_name            text     NOT NULL,
    checkpoint_day              smallint NOT NULL,
    checkpoint_date             date     NOT NULL,
    visit_count_to_checkpoint   integer  NOT NULL,
    visit_bucket                text     NOT NULL,
    target_visit_count          smallint NOT NULL,
    below_target_flag           boolean  NOT NULL,
    frozen_at_checkpoint_flag   boolean  NOT NULL,
    age_group                   text,
    membership_tenure           text     NOT NULL,
    CONSTRAINT preparation_renewal_checkpoint_key
        UNIQUE NULLS NOT DISTINCT (contract_id, checkpoint_day),
    CONSTRAINT preparation_renewal_checkpoint_day_ck
        CHECK (checkpoint_day IN (7, 14, 21, 28, 30)),
    CONSTRAINT preparation_renewal_checkpoint_visit_ck
        CHECK (visit_count_to_checkpoint >= 0),
    CONSTRAINT preparation_renewal_checkpoint_bucket_ck
        CHECK (visit_bucket IN ('0', '1', '2', '3', '4+')),
    CONSTRAINT preparation_renewal_checkpoint_target_ck
        CHECK (target_visit_count IN (1, 2, 3, 4)),
    CONSTRAINT preparation_renewal_checkpoint_age_ck
        CHECK (age_group IS NULL OR age_group IN ('Дети', 'Юниоры', 'Взрослые')),
    CONSTRAINT preparation_renewal_checkpoint_tenure_ck
        CHECK (membership_tenure IN ('New', 'Renew', 'Ex'))
);

COMMENT ON TABLE mart.preparation_renewal_checkpoint IS
    'Контракт × контрольная точка подготовки 7/14/21/28/30; посещения за 120–90 дней до окончания и current-M правило заморозок.';

REVOKE ALL ON mart.preparation_renewal_checkpoint FROM PUBLIC;

COMMIT;

-- Before COMMIT rollback: ROLLBACK. Object removal after commit is never automatic.
