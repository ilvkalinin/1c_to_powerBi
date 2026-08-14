-- REVIEW ONLY — NOT EXECUTED.
--
-- Target: fitness_dwh on VM-2.
-- Product: mart.ancillary_revenue_movement.
-- Preconditions: user approval of this SQL; a backup point; a loader that
-- reads the two confirmed source branches in one REPEATABLE READ, READ ONLY
-- snapshot and fills a temporary target table before the first refresh.
--
-- This is the first persistent object on VM-2. Execute only through the
-- approved migration mechanism after the user has reviewed this file.

BEGIN;

CREATE SCHEMA mart;

CREATE TABLE mart.ancillary_revenue_movement (
    source_kind          text            NOT NULL,
    recorder_id          text            NOT NULL,
    line_no              integer         NOT NULL,
    service_date         date            NOT NULL,
    club_id              text            NOT NULL,
    client_key           text            NOT NULL,
    client_code          text            NOT NULL,
    employee_id          text,
    employee_name        text,
    service_id           text            NOT NULL,
    service_name         text            NOT NULL,
    activity_id          text            NOT NULL,
    activity_name        text            NOT NULL,
    training_format_id   text,
    training_format_name text,
    calculation_category text            NOT NULL,
    age_category         text            NOT NULL,
    service_quantity     numeric(15, 3)  NOT NULL,
    revenue_amount       numeric(15, 2)  NOT NULL,

    CONSTRAINT ancillary_revenue_movement_pk
        PRIMARY KEY (source_kind, recorder_id, line_no),
    CONSTRAINT ancillary_revenue_movement_source_kind_ck
        CHECK (source_kind IN ('7575', '7646')),
    CONSTRAINT ancillary_revenue_movement_category_ck
        CHECK (calculation_category IN ('Прочая услуга', 'Аренда')),
    CONSTRAINT ancillary_revenue_movement_age_ck
        CHECK (age_category IN ('Дети', 'Юниоры', 'Взрослые')),
    CONSTRAINT ancillary_revenue_movement_client_code_ck
        CHECK (client_key = client_code)
);

COMMENT ON TABLE mart.ancillary_revenue_movement IS
    'Квалифицированные движения выручки ДПФУ из 1С; первый релиз.';

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Rollback after COMMIT is deliberately not automated. It needs an approved
-- change, an identified target and a verified backup/restore point; do not
-- run DROP TABLE automatically.
