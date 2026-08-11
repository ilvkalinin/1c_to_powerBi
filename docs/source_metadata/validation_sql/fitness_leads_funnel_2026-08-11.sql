-- SV-078, FL-V05: bounded read-only control of the current task-to-service key.
WITH t AS MATERIALIZED (
  SELECT _idrref,_fld1192,_fld1196rref FROM public._reference106
  WHERE _fld1191rref IN (decode('99ad9b75dc73f34911eee5eefdcdd3b4','hex'),decode('99f6efa9e59a276811f0fcebecd498be','hex'),decode('99b19ba3029d764511ef394a0464555f','hex'),decode('99ad9b75dc73f34911eee5ea6f34a13b','hex'))
    AND _fld1193>=DATE '2026-01-01' AND _fld1193<DATE '2027-01-01' AND NOT _marked
  ORDER BY _idrref LIMIT 100
), z AS MATERIALIZED (
  SELECT r._period,c._code FROM public._inforg7006 r JOIN public._reference141x1 c ON c._idrref=r._fld7008rref
  WHERE r._period>=DATE '2026-01-01' AND r._period<DATE '2027-01-01' GROUP BY 1,2
), j AS (
  SELECT t._idrref,z._code FROM t LEFT JOIN public._reference141x1 c ON c._idrref=t._fld1196rref
  LEFT JOIN z ON z._period=t._fld1192 AND z._code=c._code
)
SELECT (SELECT count(*) FROM t) AS tasks,count(*) AS joined_rows,
       count(*)-count(DISTINCT _idrref) AS join_excess,
       count(*) FILTER (WHERE _code IS NULL) AS no_raw_client_day_match FROM j;
