-- BR-045 reviewed source extract for mart.employee_presence_day; $1/$2 are [start,end).
-- Execute only through a separately approved physical-admission runner.
WITH service AS MATERIALIZED (
  SELECT child._idrref
  FROM public._reference163 child
  JOIN public._reference163 parent ON parent._idrref = child._parentidrref
  WHERE parent._description::text = 'Служебная'
), employee_client AS MATERIALIZED (
  SELECT _fld2504rref AS client_id, min(_idrref) AS employee_id
  FROM public._reference225
  WHERE _fld2504rref IS NOT NULL
  GROUP BY _fld2504rref
), events AS MATERIALIZED (
  SELECT a._period::date AS presence_date, a._fld7577rref AS club_ref,
         ec.employee_id, d._fld4172 AS start_at,
         CASE WHEN d._fld4174 = TIMESTAMP '0001-01-01 00:00:00'
                   OR d._fld4174 > date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
              THEN date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
              ELSE d._fld4174 END AS end_at
  FROM public._accumrg7575 a
  JOIN public._document325 d ON d._idrref = a._recorderrref
  JOIN public._reference132 club ON club._idrref = a._fld7577rref
  JOIN public._reference59 card ON card._idrref = a._fld7578_rrref
  JOIN service s ON s._idrref = card._fld685rref
  JOIN employee_client ec ON ec.client_id = a._fld7576rref
  WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
    AND club._description::text NOT IN ('Детский развивающий центр', 'Управляющая компания')
    AND a._period >= $1::date AND a._period < $2::date
)
SELECT presence_date, encode(club_ref, 'hex')::text AS club_id,
       encode(employee_id, 'hex')::text AS employee_id,
       sum(extract(epoch FROM end_at - start_at) / 60.0)::numeric AS presence_minutes
FROM events
GROUP BY presence_date, club_ref, employee_id;
