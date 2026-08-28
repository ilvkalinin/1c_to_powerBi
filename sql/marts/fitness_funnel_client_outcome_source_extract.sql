-- Source extract for mart.fitness_funnel_client_outcome.
-- $1 is inclusive and $2 exclusive.  BR-003 supplies the horizon.
-- BR-049 retains each qualified IP source-service event; it intentionally
-- does not apply the legacy client-day ROW_NUMBER().  No source state filter
-- is added beyond the current M/PBIT predicates.
WITH dpfu_7575_raw AS MATERIALIZED (
    SELECT r._period AS outcome_at, r._fld7576rref AS client_ref,
           r._fld7577rref AS club_ref, r._fld7579rref AS service_ref,
           r._fld7582rref AS employee_ref, r._fld7586::numeric AS amount,
           client._code::text AS client_code, club._description::text AS club_name,
           service._fld1761::text AS service_name,
           CASE WHEN membership._code IS NOT NULL THEN
                    CASE WHEN membership._fld696rref = decode('bf4b50662e88eb7b44046ebf4849976f','hex')
                         THEN 'Купон' ELSE 'Клип-Карта' END
                ELSE 'Чек' END AS payment_type
    FROM public._accumrg7575 r
    JOIN public._reference141x1 client ON client._idrref = r._fld7576rref
    JOIN public._reference132 club ON club._idrref = r._fld7577rref
    JOIN public._reference163 service ON service._idrref = r._fld7579rref
    JOIN public._reference70 activity ON activity._idrref = service._fld1733rref
    LEFT JOIN public._reference59 membership ON membership._idrref = r._fld7578_rrref
    WHERE r._period >= $1::date AND r._period < $2::date AND r._fld7586 <> 0
      AND service._fld1795rref = decode('9f007d77d46892dc47058346701d3bb6','hex')
      AND activity._fld843rref NOT IN (decode('9e10e872e49a551b4968a66b95c28905','hex'),decode('ac626c95655c992a471b27ca8f8812cd','hex'))
      AND service._description::text <> 'посещение клуба'
      AND activity._description::text IN ('Игровой зал','Восстановительный фитнес','Боевые искусства','Детский клуб','Водные программы','Групповые программы','Тренажёрный зал','Тренажерный зал')
), dpfu_7575 AS (
    SELECT concat_ws(':','DPFU7575',to_char(outcome_at,'YYYY-MM-DD"T"HH24:MI:SS.US'),
                    min(encode(client_ref,'hex')),min(encode(club_ref,'hex')),min(encode(service_ref,'hex')),min(encode(employee_ref,'hex')),payment_type) AS outcome_source_key,
           min(encode(client_ref,'hex'))::text AS client_key, outcome_at::date AS outcome_date,
           'ДПФУ'::text AS outcome_type, min(encode(club_ref,'hex'))::text AS club_id,
           min(encode(service_ref,'hex'))::text AS service_id, min(encode(employee_ref,'hex'))::text AS employee_id,
           1::numeric AS outcome_count
    FROM dpfu_7575_raw
    GROUP BY outcome_at, club_name, service_name, client_code, employee_ref, payment_type
    HAVING sum(amount) <> 0 AND payment_type <> 'Купон'
), dpfu_7646_raw AS MATERIALIZED (
    SELECT r._period AS outcome_at, r._fld7648rref AS client_ref,
           r._fld7653rref AS club_ref, r._fld7649rref AS service_ref,
           r._fld7652rref AS employee_ref, r._fld7659::numeric AS amount,
           client._code::text AS client_code, club._description::text AS club_name,
           service._fld1761::text AS service_name,
           CASE WHEN membership._code IS NOT NULL THEN
                    CASE WHEN membership._fld696rref = decode('bf4b50662e88eb7b44046ebf4849976f','hex')
                         THEN 'Купон' ELSE 'Клип-Карта' END
                ELSE 'Чек' END AS payment_type
    FROM public._accumrg7646 r
    JOIN public._reference141x1 client ON client._idrref = r._fld7648rref
    JOIN public._reference132 club ON club._idrref = r._fld7653rref
    JOIN public._reference163 service ON service._idrref = r._fld7649rref
    JOIN public._reference70 activity ON activity._idrref = service._fld1733rref
    LEFT JOIN public._reference59 membership ON membership._idrref = r._fld7655rref
    WHERE r._period >= $1::date AND r._period < $2::date AND r._fld7659 <> 0
      AND service._fld1795rref NOT IN (decode('9f007d77d46892dc47058346701d3bb6','hex'),decode('89de5e634e304b1a44efac5ab7088373','hex'),decode('baad3eba9d9fe9b441d2a1a897435c33','hex'))
      AND activity._fld843rref NOT IN (decode('9e10e872e49a551b4968a66b95c28905','hex'),decode('ac626c95655c992a471b27ca8f8812cd','hex'))
      AND service._description::text <> 'посещение клуба'
      AND activity._description::text IN ('Игровой зал','Восстановительный фитнес','Боевые искусства','Детский клуб','Водные программы','Групповые программы','Тренажёрный зал','Тренажерный зал')
), dpfu_7646 AS (
    SELECT concat_ws(':','DPFU7646',to_char(outcome_at,'YYYY-MM-DD"T"HH24:MI:SS.US'),
                    min(encode(client_ref,'hex')),min(encode(club_ref,'hex')),min(encode(service_ref,'hex')),min(encode(employee_ref,'hex')),payment_type) AS outcome_source_key,
           min(encode(client_ref,'hex'))::text AS client_key, outcome_at::date AS outcome_date,
           'ДПФУ'::text AS outcome_type, min(encode(club_ref,'hex'))::text AS club_id,
           min(encode(service_ref,'hex'))::text AS service_id, min(encode(employee_ref,'hex'))::text AS employee_id,
           1::numeric AS outcome_count
    FROM dpfu_7646_raw
    GROUP BY outcome_at, club_name, service_name, client_code, employee_ref, payment_type
    HAVING sum(amount) <> 0 AND payment_type <> 'Купон'
), ip_pz AS (
    SELECT concat_ws(':','IPPZ',encode(i._recordertref,'hex'),encode(i._recorderrref,'hex'),i._lineno::text,coalesce(vt._lineno4353::text,'none')) AS outcome_source_key,
           encode(i._fld7008rref,'hex')::text AS client_key, d._fld4306::date AS outcome_date,
           'ДПФУ'::text AS outcome_type, encode(i._fld7009rref,'hex')::text AS club_id,
           encode(i._fld7010rref,'hex')::text AS service_id, encode(d._fld4322rref,'hex')::text AS employee_id,
           1::numeric AS outcome_count
    FROM public._inforg7006 i
    JOIN public._document329 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 client ON client._idrref=i._fld7008rref
    JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld4322rref
    JOIN public._enum448 state ON state._idrref=i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref=d._idrref
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
      AND (i._fld7010rref=decode('bcd000505688c8b011ee0a8ba155d4a1','hex') OR vt._fld4358rref=decode('a0f1524d502e0d5d4c1dfeb9d5bbb3fe','hex'))
      AND state._enumorder NOT IN (2,3)
), ip_gz AS (
    SELECT concat_ws(':','IPGZ',encode(i._recordertref,'hex'),encode(i._recorderrref,'hex'),i._lineno::text) AS outcome_source_key,
           encode(i._fld7008rref,'hex')::text AS client_key, d._fld3218::date AS outcome_date,
           'ДПФУ'::text AS outcome_type, encode(i._fld7009rref,'hex')::text AS club_id,
           encode(i._fld7010rref,'hex')::text AS service_id, encode(d._fld3223rref,'hex')::text AS employee_id,
           1::numeric AS outcome_count
    FROM public._inforg7006 i
    JOIN public._document279 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 client ON client._idrref=i._fld7008rref
    JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld3223rref
    JOIN public._enum448 state ON state._idrref=i._fld7013rref
    WHERE d._fld3218 >= $1::date AND d._fld3218 < $2::date
      AND i._fld7010rref=decode('bcd000505688c8b011ee0a8ba155d4a1','hex') AND state._enumorder NOT IN (2,3)
), spt AS (
    SELECT concat_ws(':','SPT',encode(i._recordertref,'hex'),encode(i._recorderrref,'hex'),i._lineno::text) AS outcome_source_key,
           encode(i._fld7008rref,'hex')::text AS client_key, d._fld4306::date AS outcome_date,
           'СПТ'::text AS outcome_type, encode(i._fld7009rref,'hex')::text AS club_id,
           encode(i._fld7010rref,'hex')::text AS service_id, encode(d._fld4322rref,'hex')::text AS employee_id,
           1::numeric AS outcome_count
    FROM public._inforg7006 i
    JOIN public._document329 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 client ON client._idrref=i._fld7008rref
    JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld4322rref
    JOIN public._enum448 state ON state._idrref=i._fld7013rref
    JOIN public._reference163 service ON service._idrref=i._fld7010rref
    WHERE i._period >= greatest($1::date,DATE '2025-01-01') AND i._period < $2::date
      AND d._fld4306 >= $1::date AND d._fld4306 < $2::date
      AND state._enumorder=4 AND service._parentidrref=decode('4296a4bf013441d111e7cae05001072c','hex')
      AND service._description::text ILIKE '%стартов%'
      AND EXISTS (SELECT 1 FROM public._document325 v
                  WHERE v._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex')
                    AND v._fld4171rref=i._fld7008rref AND v._fld4167rref=i._fld7009rref
                    AND v._date_time>=d._fld4306::date AND v._date_time<(d._fld4306::date+INTERVAL '1 day'))
), outcomes AS (
    SELECT * FROM dpfu_7575 UNION ALL SELECT * FROM dpfu_7646 UNION ALL SELECT * FROM ip_pz UNION ALL SELECT * FROM ip_gz UNION ALL SELECT * FROM spt
)
SELECT outcome_source_key,client_key,outcome_date,outcome_type,club_id,service_id,employee_id,outcome_count
FROM outcomes;
