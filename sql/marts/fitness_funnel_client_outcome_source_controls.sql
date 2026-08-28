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
