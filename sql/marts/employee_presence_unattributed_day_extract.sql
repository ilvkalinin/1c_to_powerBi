-- Exact BR-043 source extract for non-personal employee presence; $1/$2 are [start,end).
WITH service AS MATERIALIZED (
  SELECT c._idrref FROM public._reference163 c JOIN public._reference163 p ON p._idrref = c._parentidrref
  WHERE p._description::text = 'Служебная'
), employee_client AS MATERIALIZED (
  SELECT _fld2504rref AS client_id, count(*) AS employee_count FROM public._reference225
  WHERE _fld2504rref IS NOT NULL GROUP BY _fld2504rref
), events AS MATERIALIZED (
  SELECT a._period::date AS presence_date, a._fld7577rref AS club_ref,
         CASE WHEN ec.client_id IS NULL THEN 'NO_EMPLOYEE' ELSE 'MULTIPLE_EMPLOYEES' END AS attribution_status,
         d._fld4172 AS start_at,
         CASE WHEN d._fld4174 = TIMESTAMP '0001-01-01 00:00:00'
                   OR d._fld4174 > date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
              THEN date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
              ELSE d._fld4174 END AS end_at
  FROM public._accumrg7575 a JOIN public._document325 d ON d._idrref = a._recorderrref
  JOIN public._reference132 club ON club._idrref = a._fld7577rref
  JOIN public._reference59 card ON card._idrref = a._fld7578_rrref JOIN service s ON s._idrref = card._fld685rref
  LEFT JOIN employee_client ec ON ec.client_id = a._fld7576rref
  WHERE (ec.client_id IS NULL OR ec.employee_count > 1)
    AND d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
    AND club._description::text NOT IN ('Детский развивающий центр', 'Управляющая компания')
    AND a._period >= $1::date AND a._period < $2::date
)
SELECT presence_date, encode(club_ref, 'hex')::text AS club_id, attribution_status,
       sum(extract(epoch FROM end_at - start_at) / 60.0)::numeric AS presence_minutes
FROM events GROUP BY presence_date, club_ref, attribution_status;
