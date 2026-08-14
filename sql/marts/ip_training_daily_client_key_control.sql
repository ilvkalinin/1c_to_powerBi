-- Source guard for mart.ip_training_daily client_key.
-- The runner binds $1 = BR-003 horizon_start and $2 = horizon_end in the
-- same REPEATABLE READ, READ ONLY snapshot as the extract. Expected result:
-- total_clients > 0; blank_codes = 0; duplicate_codes = 0.

WITH pz AS (
    SELECT encode(i._fld7008rref, 'hex') AS source_client_id,
           CAST(client._code AS varchar(1000)) AS client_key
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._document329 d ON d._idrref = i._fld7007_rrref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref = d._idrref
    WHERE d._fld4306 >= $1::date
      AND d._fld4306 < $2::date
      AND (encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
        OR encode(vt._fld4358rref, 'hex') = 'a0f1524d502e0d5d4c1dfeb9d5bbb3fe')
      AND state._enumorder NOT IN (2, 3)
), gp AS (
    SELECT encode(i._fld7008rref, 'hex') AS source_client_id,
           CAST(client._code AS varchar(1000)) AS client_key
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._document279 d ON d._idrref = i._fld7007_rrref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    WHERE d._fld3218 >= $1::date
      AND d._fld3218 < $2::date
      AND encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
      AND state._enumorder NOT IN (2, 3)
), clients AS (
    SELECT client_key, count(DISTINCT source_client_id) AS source_id_count
    FROM (SELECT * FROM pz UNION ALL SELECT * FROM gp) q
    GROUP BY client_key
)
SELECT count(*)::bigint AS total_clients,
       count(*) FILTER (WHERE client_key IS NULL OR btrim(client_key) = '')::bigint AS blank_codes,
       count(*) FILTER (WHERE source_id_count > 1)::bigint AS duplicate_codes
FROM clients;
