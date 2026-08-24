-- REVIEWED Stage-3 DDL — minimal date facts for «Новички и гостевые визиты».
-- Objects: mart.new_first_visit, mart.guest_visit_conversion.
-- Apply only through scripts/load_newcomer_guest_visits_minimal_date_facts.py.

BEGIN;

CREATE TABLE mart.new_first_visit (
    contract_id       text PRIMARY KEY,
    first_visit_date  date NOT NULL
);

CREATE TABLE mart.guest_visit_conversion (
    client_id                 text NOT NULL,
    client_code               text,
    guest_visit_date          date NOT NULL,
    accuniq_same_day_flag     boolean NOT NULL,
    purchase_activation_date  date,
    purchase_lag_days         smallint,
    PRIMARY KEY (client_id, guest_visit_date),
    CHECK (
        (purchase_activation_date IS NULL AND purchase_lag_days IS NULL)
        OR (
            purchase_activation_date = guest_visit_date + purchase_lag_days
            AND purchase_lag_days BETWEEN 0 AND 44
        )
    )
);

REVOKE ALL ON mart.new_first_visit, mart.guest_visit_conversion FROM PUBLIC;

COMMIT;
