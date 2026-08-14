-- APPLIED 2026-08-14 after separate explicit user approval.
-- Target: fitness_dwh on VM-2.
-- Product: mart.ip_training_daily.
-- Preconditions used: S3-IP-ADMISSION-001 passed; mart schema existed; this
-- table was absent; the reviewed loader had not yet run.

BEGIN;

CREATE TABLE mart.ip_training_daily (
    training_date  date    NOT NULL,
    club_id        text    NOT NULL,
    employee_id    text    NOT NULL,
    employee_name  text    NOT NULL,
    client_key     text    NOT NULL,
    client_code    text    NOT NULL,
    service_id     text    NOT NULL,
    service_name   text    NOT NULL,
    training_count bigint  NOT NULL,

    CONSTRAINT ip_training_daily_pk
        PRIMARY KEY (training_date, club_id, employee_id, client_key, service_id),
    CONSTRAINT ip_training_daily_count_ck
        CHECK (training_count > 0),
    CONSTRAINT ip_training_daily_client_code_ck
        CHECK (client_key = client_code)
);

COMMENT ON TABLE mart.ip_training_daily IS
    'Квалифицированные тренировки ИП: дата × клуб × сотрудник × клиент × услуга.';

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Rollback after COMMIT is deliberately not automated. It requires a separate
-- approved change, an identified object, and a verified backup/restore point.
