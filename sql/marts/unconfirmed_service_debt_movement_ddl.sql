BEGIN;
CREATE TABLE IF NOT EXISTS mart.unconfirmed_service_debt_movement (
    debt_event_at timestamp NOT NULL, recorder_type bytea NOT NULL, recorder_id bytea NOT NULL,
    recorder_line_no integer NOT NULL, record_kind smallint NOT NULL, client_key bytea NOT NULL,
    client_code text, client_name text, club_id bytea NOT NULL, club_name text,
    prebooking_id bytea NOT NULL, service_id bytea NOT NULL, service_name text,
    employee_id bytea NOT NULL, employee_name text, service_start_at timestamp NOT NULL,
    service_end_at timestamp NOT NULL, quantity_delta numeric(10,0) NOT NULL,
    amount_delta numeric(15,2) NOT NULL,
    CONSTRAINT unconfirmed_service_debt_movement_pk PRIMARY KEY (debt_event_at, recorder_type, recorder_id, recorder_line_no)
);
COMMIT;
