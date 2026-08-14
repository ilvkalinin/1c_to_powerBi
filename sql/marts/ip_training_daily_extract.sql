-- Source extract for mart.ip_training_daily.
-- REVIEW ONLY. The runner binds $1 = BR-003 horizon_start and
-- $2 = BR-003 horizon_end, opens one REPEATABLE READ, READ ONLY source
-- snapshot, then streams these explicit target columns to a VM-2 temp stage.
-- PZ VT4352 multiplicity is intentionally retained by BR-018.

WITH pz AS (
    SELECT d._fld4306::date AS training_date,
           encode(i._fld7009rref, 'hex') AS club_id,
           encode(d._fld4322rref, 'hex') AS employee_id,
           CAST(employee._description AS varchar(1000)) AS employee_name,
           CAST(client._code AS varchar(1000)) AS client_key,
           CAST(client._code AS varchar(1000)) AS client_code,
           encode(i._fld7010rref, 'hex') AS service_id,
           CAST(service._description AS varchar(1000)) AS service_name
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._reference163 service ON service._idrref = i._fld7010rref
    JOIN public._document329 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld4322rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref = d._idrref
    WHERE d._fld4306 >= $1::date
      AND d._fld4306 < $2::date
      AND (encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
        OR encode(vt._fld4358rref, 'hex') = 'a0f1524d502e0d5d4c1dfeb9d5bbb3fe')
      AND state._enumorder NOT IN (2, 3)
), gp AS (
    SELECT d._fld3218::date AS training_date,
           encode(i._fld7009rref, 'hex') AS club_id,
           encode(d._fld3223rref, 'hex') AS employee_id,
           CAST(employee._description AS varchar(1000)) AS employee_name,
           CAST(client._code AS varchar(1000)) AS client_key,
           CAST(client._code AS varchar(1000)) AS client_code,
           encode(i._fld7010rref, 'hex') AS service_id,
           CAST(service._description AS varchar(1000)) AS service_name
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._reference163 service ON service._idrref = i._fld7010rref
    JOIN public._document279 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld3223rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    WHERE d._fld3218 >= $1::date
      AND d._fld3218 < $2::date
      AND encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
      AND state._enumorder NOT IN (2, 3)
), raw AS (
    SELECT * FROM pz
    UNION ALL
    SELECT * FROM gp
)
SELECT training_date, club_id, employee_id,
       max(employee_name) AS employee_name,
       client_key, client_code, service_id,
       max(service_name) AS service_name,
       count(*)::bigint AS training_count
FROM raw
GROUP BY training_date, club_id, employee_id, client_key, client_code, service_id;
