-- Executed only by load_unconfirmed_service_debt_movement_incremental.py
-- inside one target transaction. Parameters are BR-003 start/end and the
-- bounded window start/end. Rows inside the window are replaced atomically;
-- rows outside BR-003 are removed and older in-horizon history is preserved.
DELETE FROM mart.unconfirmed_service_debt_movement
WHERE debt_event_at < %s::timestamp
   OR debt_event_at >= %s::timestamp
   OR (debt_event_at >= %s::timestamp AND debt_event_at < %s::timestamp);

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
