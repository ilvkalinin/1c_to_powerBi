-- REVIEWED Stage-3 DDL: mart.renewal_management_contract.
-- Apply only through scripts/load_renewal_management_contract.py.
-- Grain: one retained source membership contract per row.

BEGIN;

CREATE TABLE mart.renewal_management_contract (
    expiring_contract_id          text        NOT NULL,
    expiring_contract_code        text        NOT NULL,
    client_id                     text        NOT NULL,
    client_code                   text        NOT NULL,
    client_name                   text        NOT NULL,
    client_phone                  text,
    birth_date                    date,
    membership_start_date         date        NOT NULL,
    membership_end_date           date        NOT NULL,
    contract_end_month            date        NOT NULL,
    membership_term_days          numeric     NOT NULL,
    access_club_id                text        NOT NULL,
    purchase_price                numeric,
    visit_count                   bigint      NOT NULL,
    usage_rate                    numeric,
    average_monthly_visits        numeric,
    renewed_by_month_close_flag   boolean     NOT NULL,
    renewed_current_flag          boolean     NOT NULL,
    next_contract_id              text,
    next_contract_code            text,
    renewal_activation_date       date,
    next_contract_start_date      date,
    next_contract_term_days       numeric,
    renewal_type                  text        NOT NULL,
    renewal_lead_lag_days         integer,
    return_days                   integer,
    return_bucket                 text,
    current_rating                text,
    current_tenure                text,
    last_interaction_at           timestamp   without time zone,
    last_interaction_type         text,
    current_funnel_stage          text,
    current_fail_reason           text,
    CONSTRAINT renewal_management_contract_pkey PRIMARY KEY (expiring_contract_id),
    CONSTRAINT renewal_management_contract_code_key UNIQUE (expiring_contract_code),
    CONSTRAINT renewal_management_contract_dates_ck
        CHECK (membership_end_date >= membership_start_date
               AND contract_end_month = date_trunc('month', membership_end_date)::date),
    CONSTRAINT renewal_management_contract_term_ck CHECK (membership_term_days >= 30),
    CONSTRAINT renewal_management_contract_visit_ck CHECK (visit_count >= 0),
    CONSTRAINT renewal_management_contract_next_term_ck
        CHECK (next_contract_term_days IS NULL OR next_contract_term_days >= 1),
    CONSTRAINT renewal_management_contract_renewal_type_ck
        CHECK (renewal_type IN ('Не продлен', 'Платное продление',
                                'Бесплатное длинное продление', 'Бесплатное короткое продление')),
    CONSTRAINT renewal_management_contract_return_ck
        CHECK ((renewal_activation_date IS NULL AND return_days IS NULL AND return_bucket IS NULL)
               OR (renewal_activation_date IS NOT NULL AND
                   (return_days IS NULL OR return_days > 0) AND
                   return_bucket IN ('До окончания', '0–30', '31–60', '61–90', '91–180', '181+')))
);

COMMENT ON TABLE mart.renewal_management_contract IS
    'Текущая когорта продления: один исходный абонемент, current-M predicates и BR-050 tie-break.';

REVOKE ALL ON mart.renewal_management_contract FROM PUBLIC;

COMMIT;

-- Before COMMIT rollback: ROLLBACK. Object removal after commit is never automatic.
