-- APPLIED 2026-08-14 after separate explicit user approval.
-- Target: VM-2 / fitness_dwh. Product: mart.ip_revenue_daily.
-- Preconditions: S3-IP-REVENUE-001 passed; mart schema exists; table is absent.
-- Execute only after a separate explicit DDL approval. The first data load needs
-- its own separate DML approval.

BEGIN;

CREATE TABLE mart.ip_revenue_daily (
    revenue_date   date          NOT NULL,
    club_id        text,
    service_id     text          NOT NULL,
    service_name   text          NOT NULL,
    revenue_amount numeric(18,2) NOT NULL,

    CONSTRAINT ip_revenue_daily_uk
        UNIQUE NULLS NOT DISTINCT (revenue_date, club_id, service_id)
);

COMMENT ON TABLE mart.ip_revenue_daily IS
    'Выручка ИП: дата оплаты × клуб движения (может отсутствовать) × услуга договора.';

COMMIT;

-- Rollback before COMMIT: ROLLBACK.
-- Rollback after COMMIT is deliberately not automated. It requires a separate
-- approved change, an identified object, and a verified backup/restore point.
