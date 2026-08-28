-- Future physical DDL for mart.fitness_funnel_client_start.
-- Execute only in the separately approved physical-admission target transaction.
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE mart.fitness_funnel_client_start (
    client_key text NOT NULL,
    membership_start_date date NOT NULL,
    access_club_id text NOT NULL,
    tenure_type text NOT NULL,
    client_count smallint NOT NULL DEFAULT 1,
    CONSTRAINT fitness_funnel_client_start_pkey
        PRIMARY KEY (client_key, membership_start_date),
    CONSTRAINT fitness_funnel_client_start_tenure_check
        CHECK (tenure_type IN ('New', 'Ex', 'Renew')),
    CONSTRAINT fitness_funnel_client_start_client_count_check
        CHECK (client_count = 1)
);

REVOKE ALL ON mart.fitness_funnel_client_start FROM PUBLIC;
