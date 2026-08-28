-- REVIEWED DDL for mart.contract_usage.
-- Execute only through the separately approved physical-admission runner.
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE mart.contract_usage (
    contract_id text PRIMARY KEY,
    contract_code text NOT NULL UNIQUE,
    membership_start_date date NOT NULL,
    membership_end_date date NOT NULL,
    contract_end_month date NOT NULL,
    membership_term_days numeric,
    active_calendar_months integer NOT NULL,
    visit_count bigint NOT NULL,
    usage_rate numeric,
    average_monthly_visits numeric,
    is_finalized boolean NOT NULL,
    finalized_month date,
    CONSTRAINT contract_usage_membership_interval_check
        CHECK (membership_end_date >= membership_start_date),
    CONSTRAINT contract_usage_end_month_check
        CHECK (contract_end_month = date_trunc('month', membership_end_date)::date),
    CONSTRAINT contract_usage_active_months_check
        CHECK (active_calendar_months >= 1),
    CONSTRAINT contract_usage_visit_count_check
        CHECK (visit_count > 0),
    CONSTRAINT contract_usage_finalization_shape_check
        CHECK ((is_finalized AND finalized_month = contract_end_month)
               OR (NOT is_finalized AND finalized_month IS NULL))
);

REVOKE ALL ON mart.contract_usage FROM PUBLIC;
