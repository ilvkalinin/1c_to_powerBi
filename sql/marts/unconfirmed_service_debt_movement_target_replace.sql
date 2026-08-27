-- Executed only by load_unconfirmed_service_debt_movement.py inside its one
-- atomic target transaction. Full retained horizon replacement is intentional:
-- it prevents stale and future movements outside BR-003 from surviving reruns.
DELETE FROM mart.unconfirmed_service_debt_movement;

INSERT INTO mart.unconfirmed_service_debt_movement (
    debt_event_at, recorder_type, recorder_id, recorder_line_no, record_kind,
    client_key, client_code, client_name, club_id, club_name, prebooking_id,
    service_id, service_name, employee_id, employee_name, service_start_at,
    service_end_at, quantity_delta, amount_delta
)
SELECT debt_event_at, recorder_type, recorder_id, recorder_line_no, record_kind,
       client_key, client_code, client_name, club_id, club_name, prebooking_id,
       service_id, service_name, employee_id, employee_name, service_start_at,
       service_end_at, quantity_delta, amount_delta
FROM _unconfirmed_service_debt_movement_stage;
