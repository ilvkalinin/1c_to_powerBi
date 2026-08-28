-- Future physical-admission DDL only.  Do not run in technical review.
CREATE SCHEMA IF NOT EXISTS mart;
CREATE TABLE mart.fitness_funnel_client_outcome (
    outcome_source_key text NOT NULL,
    client_key text NOT NULL,
    outcome_date date NOT NULL,
    outcome_type text NOT NULL,
    club_id text NOT NULL,
    service_id text NOT NULL,
    employee_id text NOT NULL,
    outcome_count numeric(18,0) NOT NULL,
    CONSTRAINT fitness_funnel_client_outcome_pk PRIMARY KEY (outcome_source_key),
    CONSTRAINT fitness_funnel_client_outcome_type_ck CHECK (outcome_type IN ('СПТ','ДПФУ')),
    CONSTRAINT fitness_funnel_client_outcome_count_ck CHECK (outcome_count = 1)
);
REVOKE ALL ON TABLE mart.fitness_funnel_client_outcome FROM PUBLIC;
COMMENT ON TABLE mart.fitness_funnel_client_outcome IS
    'Исходы фитнес-воронки: source-service event; BR-049 сохраняет разные услуги отдельными строками.';
