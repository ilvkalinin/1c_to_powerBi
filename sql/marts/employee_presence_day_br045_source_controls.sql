-- Independent aggregate source controls for BR-045; $1/$2 are [start,end).
-- This path derives controls independently from the COPY extract and is not executed in planning.
WITH service_cards AS MATERIALIZED (
  SELECT c._idrref AS service_id
  FROM public._reference163 c
  JOIN public._reference163 p ON p._idrref = c._parentidrref
  WHERE p._description::text = 'Служебная'
), chosen_employee AS MATERIALIZED (
  SELECT _fld2504rref AS client_id, min(_idrref) AS chosen_employee_id,
         count(*) AS employee_link_count
  FROM public._reference225
  WHERE _fld2504rref IS NOT NULL
  GROUP BY _fld2504rref
), qualified_visits AS MATERIALIZED (
  SELECT a._recorderrref AS visit_id, a._period::date AS presence_date,
         a._fld7577rref AS club_ref, ce.chosen_employee_id, ce.employee_link_count,
         extract(epoch FROM
           (CASE WHEN d._fld4174 = TIMESTAMP '0001-01-01 00:00:00'
                      OR d._fld4174 > date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
                 THEN date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
                 ELSE d._fld4174 END) - d._fld4172) / 60.0 AS minutes
  FROM public._accumrg7575 a
  JOIN public._document325 d ON d._idrref = a._recorderrref
  JOIN public._reference132 club ON club._idrref = a._fld7577rref
  JOIN public._reference59 card ON card._idrref = a._fld7578_rrref
  JOIN service_cards sc ON sc.service_id = card._fld685rref
  LEFT JOIN chosen_employee ce ON ce.client_id = a._fld7576rref
  WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
    AND club._description::text NOT IN ('Детский развивающий центр', 'Управляющая компания')
    AND a._period >= $1::date AND a._period < $2::date
), visit_minutes AS (
  SELECT visit_id, presence_date, club_ref, chosen_employee_id, employee_link_count, minutes
  FROM qualified_visits
  WHERE chosen_employee_id IS NOT NULL
), grouped AS (
  SELECT presence_date, club_ref, chosen_employee_id, sum(minutes)::numeric AS presence_minutes
  FROM visit_minutes GROUP BY 1, 2, 3
)
SELECT (SELECT count(*) FROM grouped)::bigint AS target_grain_rows,
       (SELECT coalesce(sum(presence_minutes), 0) FROM grouped)::numeric AS total_presence_minutes,
       (SELECT min(presence_date) FROM grouped) AS min_presence_date,
       (SELECT max(presence_date) FROM grouped) AS max_presence_date,
       (SELECT count(DISTINCT visit_id) FROM visit_minutes)::bigint AS retained_visit_ids,
       (SELECT count(DISTINCT visit_id) FROM qualified_visits WHERE chosen_employee_id IS NULL)::bigint AS no_link_visit_ids,
       (SELECT count(DISTINCT visit_id) FROM visit_minutes WHERE employee_link_count > 1)::bigint AS multi_link_visit_ids;
