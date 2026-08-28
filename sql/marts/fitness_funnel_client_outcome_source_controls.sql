-- Source-side contract controls for mart.fitness_funnel_client_outcome.
-- $1 inclusive, $2 exclusive. Run in the same REPEATABLE READ snapshot as
-- the extract. They are branch checks, not a target load.
WITH ip_pz AS (
    SELECT concat_ws(':','IPPZ',encode(i._recordertref,'hex'),encode(i._recorderrref,'hex'),i._lineno::text,coalesce(vt._lineno4353::text,'none')) AS source_key,
           d._fld4306::date AS outcome_date, i._fld7008rref client_ref,
           i._fld7009rref club_ref, i._fld7010rref service_ref, d._fld4322rref employee_ref
    FROM public._inforg7006 i JOIN public._document329 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 c ON c._idrref=i._fld7008rref JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld4322rref JOIN public._enum448 state ON state._idrref=i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref=d._idrref
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
      AND (i._fld7010rref=decode('bcd000505688c8b011ee0a8ba155d4a1','hex') OR vt._fld4358rref=decode('a0f1524d502e0d5d4c1dfeb9d5bbb3fe','hex'))
      AND state._enumorder NOT IN (2,3)
), ip_gz AS (
    SELECT concat_ws(':','IPGZ',encode(i._recordertref,'hex'),encode(i._recorderrref,'hex'),i._lineno::text) AS source_key,
           d._fld3218::date AS outcome_date, i._fld7008rref client_ref,
           i._fld7009rref club_ref, i._fld7010rref service_ref, d._fld3223rref employee_ref
    FROM public._inforg7006 i JOIN public._document279 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 c ON c._idrref=i._fld7008rref JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld3223rref JOIN public._enum448 state ON state._idrref=i._fld7013rref
    WHERE d._fld3218 >= $1::date AND d._fld3218 < $2::date
      AND i._fld7010rref=decode('bcd000505688c8b011ee0a8ba155d4a1','hex') AND state._enumorder NOT IN (2,3)
), ip AS (SELECT 'IPPZ' AS branch,* FROM ip_pz UNION ALL SELECT 'IPGZ',* FROM ip_gz)
SELECT 'FF-O01'::text AS control_id, count(*)::bigint AS source_rows,
       count(*)-count(DISTINCT source_key)::bigint AS duplicate_source_keys,
       count(*) FILTER (WHERE client_ref IS NULL OR club_ref IS NULL OR service_ref IS NULL OR employee_ref IS NULL OR outcome_date IS NULL)::bigint AS required_null_rows,
       count(*) FILTER (WHERE outcome_date < $1::date OR outcome_date >= $2::date)::bigint AS horizon_rows
FROM ip;

WITH branch_keys AS (
    SELECT '7575'::text branch,r._recordertref,r._recorderrref,r._lineno FROM public._accumrg7575 r WHERE r._period >= $1::date AND r._period < $2::date
    UNION ALL SELECT '7646',r._recordertref,r._recorderrref,r._lineno FROM public._accumrg7646 r WHERE r._period >= $1::date AND r._period < $2::date
    UNION ALL SELECT '7006',r._recordertref,r._recorderrref,r._lineno FROM public._inforg7006 r WHERE r._period >= $1::date AND r._period < $2::date
)
SELECT 'FF-O02'::text AS control_id,count(*)::bigint AS checked_rows,
       count(*)-count(DISTINCT (branch,_recordertref,_recorderrref,_lineno))::bigint AS duplicate_physical_keys
FROM branch_keys;

-- Independent expected output by source branch.  This deliberately does not
-- call the extract under test: it independently re-applies each current-M
-- qualification and legacy register aggregation, then target reconciliation
-- compares these branch counts with outcome_source_key prefixes.
WITH dpfu_7575_groups AS (
    SELECT r._period AS outcome_at
    FROM public._accumrg7575 r
    JOIN public._reference141x1 client ON client._idrref=r._fld7576rref
    JOIN public._reference132 club ON club._idrref=r._fld7577rref
    JOIN public._reference163 service ON service._idrref=r._fld7579rref
    JOIN public._reference70 activity ON activity._idrref=service._fld1733rref
    LEFT JOIN public._reference59 membership ON membership._idrref=r._fld7578_rrref
    WHERE r._period >= $1::date AND r._period < $2::date AND r._fld7586<>0
      AND service._fld1795rref=decode('9f007d77d46892dc47058346701d3bb6','hex')
      AND activity._fld843rref NOT IN (decode('9e10e872e49a551b4968a66b95c28905','hex'),decode('ac626c95655c992a471b27ca8f8812cd','hex'))
      AND service._description::text<>'посещение клуба'
      AND activity._description::text IN ('Игровой зал','Восстановительный фитнес','Боевые искусства','Детский клуб','Водные программы','Групповые программы','Тренажёрный зал','Тренажерный зал')
    GROUP BY r._period,club._description,service._fld1761,client._code,r._fld7582rref,
             CASE WHEN membership._code IS NOT NULL THEN CASE WHEN membership._fld696rref=decode('bf4b50662e88eb7b44046ebf4849976f','hex') THEN 'Купон' ELSE 'Клип-Карта' END ELSE 'Чек' END
    HAVING sum(r._fld7586::numeric)<>0
       AND (CASE WHEN membership._code IS NOT NULL THEN CASE WHEN membership._fld696rref=decode('bf4b50662e88eb7b44046ebf4849976f','hex') THEN 'Купон' ELSE 'Клип-Карта' END ELSE 'Чек' END)<>'Купон'
), dpfu_7646_groups AS (
    SELECT r._period AS outcome_at
    FROM public._accumrg7646 r
    JOIN public._reference141x1 client ON client._idrref=r._fld7648rref
    JOIN public._reference132 club ON club._idrref=r._fld7653rref
    JOIN public._reference163 service ON service._idrref=r._fld7649rref
    JOIN public._reference70 activity ON activity._idrref=service._fld1733rref
    LEFT JOIN public._reference59 membership ON membership._idrref=r._fld7655rref
    WHERE r._period >= $1::date AND r._period < $2::date AND r._fld7659<>0
      AND service._fld1795rref NOT IN (decode('9f007d77d46892dc47058346701d3bb6','hex'),decode('89de5e634e304b1a44efac5ab7088373','hex'),decode('baad3eba9d9fe9b441d2a1a897435c33','hex'))
      AND activity._fld843rref NOT IN (decode('9e10e872e49a551b4968a66b95c28905','hex'),decode('ac626c95655c992a471b27ca8f8812cd','hex'))
      AND service._description::text<>'посещение клуба'
      AND activity._description::text IN ('Игровой зал','Восстановительный фитнес','Боевые искусства','Детский клуб','Водные программы','Групповые программы','Тренажёрный зал','Тренажерный зал')
    GROUP BY r._period,club._description,service._fld1761,client._code,r._fld7652rref,
             CASE WHEN membership._code IS NOT NULL THEN CASE WHEN membership._fld696rref=decode('bf4b50662e88eb7b44046ebf4849976f','hex') THEN 'Купон' ELSE 'Клип-Карта' END ELSE 'Чек' END
    HAVING sum(r._fld7659::numeric)<>0
       AND (CASE WHEN membership._code IS NOT NULL THEN CASE WHEN membership._fld696rref=decode('bf4b50662e88eb7b44046ebf4849976f','hex') THEN 'Купон' ELSE 'Клип-Карта' END ELSE 'Чек' END)<>'Купон'
), ip_pz AS (
    SELECT d._fld4306::date AS outcome_date
    FROM public._inforg7006 i JOIN public._document329 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 c ON c._idrref=i._fld7008rref JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld4322rref JOIN public._enum448 state ON state._idrref=i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref=d._idrref
    WHERE d._fld4306 >= $1::date AND d._fld4306 < $2::date
      AND (i._fld7010rref=decode('bcd000505688c8b011ee0a8ba155d4a1','hex') OR vt._fld4358rref=decode('a0f1524d502e0d5d4c1dfeb9d5bbb3fe','hex'))
      AND state._enumorder NOT IN (2,3)
), ip_gz AS (
    SELECT d._fld3218::date AS outcome_date
    FROM public._inforg7006 i JOIN public._document279 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 c ON c._idrref=i._fld7008rref JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld3223rref JOIN public._enum448 state ON state._idrref=i._fld7013rref
    WHERE d._fld3218 >= $1::date AND d._fld3218 < $2::date
      AND i._fld7010rref=decode('bcd000505688c8b011ee0a8ba155d4a1','hex') AND state._enumorder NOT IN (2,3)
), spt AS (
    SELECT d._fld4306::date AS outcome_date
    FROM public._inforg7006 i JOIN public._document329 d ON d._idrref=i._fld7007_rrref
    JOIN public._reference141x1 c ON c._idrref=i._fld7008rref JOIN public._reference132 club ON club._idrref=i._fld7009rref
    JOIN public._reference225 employee ON employee._idrref=d._fld4322rref JOIN public._enum448 state ON state._idrref=i._fld7013rref
    JOIN public._reference163 service ON service._idrref=i._fld7010rref
    WHERE i._period >= greatest($1::date,DATE '2025-01-01') AND i._period < $2::date
      AND d._fld4306 >= $1::date AND d._fld4306 < $2::date AND state._enumorder=4
      AND service._parentidrref=decode('4296a4bf013441d111e7cae05001072c','hex') AND service._description::text ILIKE '%стартов%'
      AND EXISTS (SELECT 1 FROM public._document325 v WHERE v._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex')
                  AND v._fld4171rref=i._fld7008rref AND v._fld4167rref=i._fld7009rref
                  AND v._date_time>=d._fld4306::date AND v._date_time<(d._fld4306::date+INTERVAL '1 day'))
)
SELECT 'FF-O03'::text AS control_id,'DPFU7575'::text AS branch,count(*)::bigint AS expected_rows,min(outcome_at)::date AS min_date,max(outcome_at)::date AS max_date FROM dpfu_7575_groups
UNION ALL SELECT 'FF-O03','DPFU7646',count(*)::bigint,min(outcome_at)::date,max(outcome_at)::date FROM dpfu_7646_groups
UNION ALL SELECT 'FF-O03','IPPZ',count(*)::bigint,min(outcome_date)::date,max(outcome_date)::date FROM ip_pz
UNION ALL SELECT 'FF-O03','IPGZ',count(*)::bigint,min(outcome_date)::date,max(outcome_date)::date FROM ip_gz
UNION ALL SELECT 'FF-O03','SPT',count(*)::bigint,min(outcome_date)::date,max(outcome_date)::date FROM spt;
