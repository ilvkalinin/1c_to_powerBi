-- Reviewed Stage-3 DDL: forward observed states, not reconstructed source history.
BEGIN;

CREATE TABLE mart.renewal_management_contract_observation (
    expiring_contract_id            text        NOT NULL,
    observed_at                     timestamptz NOT NULL,
    observation_kind                text        NOT NULL,
    state_hash                      text        NOT NULL,
    membership_end_date             date,
    contract_end_month              date,
    client_id                       text,
    access_club_id                  text,
    next_contract_id                text,
    next_contract_code              text,
    renewal_activation_date         date,
    next_contract_start_date        date,
    next_contract_term_days         numeric,
    renewal_type                    text,
    renewed_by_month_close_flag     boolean,
    renewed_current_flag            boolean,
    renewal_lead_lag_days           integer,
    return_days                     integer,
    return_bucket                   text,
    current_rating                  text,
    current_tenure                  text,
    last_interaction_at             timestamp without time zone,
    last_interaction_type           text,
    current_funnel_stage            text,
    current_fail_reason             text,
    CONSTRAINT renewal_management_contract_observation_pkey
        PRIMARY KEY (expiring_contract_id, observed_at),
    CONSTRAINT renewal_management_contract_observation_kind_ck
        CHECK (observation_kind IN ('BASELINE', 'CHANGED', 'REMOVED')),
    CONSTRAINT renewal_management_contract_observation_hash_ck
        CHECK (state_hash ~ '^[0-9a-f]{32}$'),
    CONSTRAINT renewal_management_contract_observation_current_state_ck
        CHECK (
            observation_kind = 'REMOVED'
            OR (
                membership_end_date IS NOT NULL
                AND contract_end_month IS NOT NULL
                AND client_id IS NOT NULL
                AND access_club_id IS NOT NULL
                AND renewal_type IS NOT NULL
                AND renewed_by_month_close_flag IS NOT NULL
                AND renewed_current_flag IS NOT NULL
            )
        )
);

COMMENT ON TABLE mart.renewal_management_contract_observation IS
    'Forward observed current-mart states. Not a reconstruction of historical 1C state.';

REVOKE ALL ON mart.renewal_management_contract_observation FROM PUBLIC;

COMMIT;

-- Before COMMIT rollback: ROLLBACK. Object removal after commit is never automatic.
