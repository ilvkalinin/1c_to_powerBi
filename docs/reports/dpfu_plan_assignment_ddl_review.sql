-- APPLIED 2026-08-14 after separate explicit user approval.
-- Target: VM-2 / fitness_dwh. Product: mart.dpfu_plan_assignment.
-- Preconditions: S3-PLAN-001 passed; mart schema exists; table is absent.
-- Execute only after separate explicit DDL approval. The first data load needs
-- its own separate explicit DML approval.

BEGIN;

CREATE TABLE mart.dpfu_plan_assignment (
    plan_date               date          NOT NULL,
    club_id                 text          NOT NULL,
    activity_id             text          NOT NULL,
    employee_id             text          NOT NULL,
    planned_client_key      text          NOT NULL,
    planned_client_code     text          NOT NULL,
    plan_line_discriminator text          NOT NULL,
    planned_revenue         numeric(18,2) NOT NULL,

    CONSTRAINT dpfu_plan_assignment_pk
        PRIMARY KEY (
            plan_date, club_id, activity_id, employee_id,
            planned_client_key, plan_line_discriminator
        )
);

COMMENT ON TABLE mart.dpfu_plan_assignment IS
    'План ДПФУ: дата × клуб × направление × тренер × клиент × различитель строки.';

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Rollback after COMMIT is deliberately not automated. It requires a separate
-- approved change, an identified object, and a verified backup/restore point.
