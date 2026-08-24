-- REVIEWED source-side compact extract for mart.club_attendance_hourly.
-- Both sections run in one REPEATABLE READ, READ ONLY snapshot.
-- $1 is the inclusive BR-003 timestamp and $2 is the exclusive timestamp.

-- name: hourly
WITH qualified_visits AS MATERIALIZED (
    SELECT a._period::date AS visit_date,
           encode(a._fld7577rref, 'hex') AS club_id,
           extract(hour FROM d._fld4172)::smallint AS start_hour,
           extract(hour FROM d._fld4174)::smallint AS end_hour,
           encode(client._fld1527rref, 'hex') AS sex_code,
           CASE
               WHEN client._fld1507::date = DATE '0001-01-01' THEN NULL
               ELSE extract(year FROM age(a._period::date, client._fld1507::date))::smallint
           END AS age_years,
           extract(epoch FROM (
               CASE
                   WHEN d._fld4174 IS NULL OR d._fld4174 <= timestamp '0001-01-01'
                       THEN date_trunc('day', d._fld4172) + interval '23:59:59'
                   ELSE d._fld4174
               END - d._fld4172
           )) / 60.0 AS club_minutes
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d
      ON d._idrref = a._recorderrref
    JOIN public._reference132 AS club
      ON club._idrref = a._fld7577rref
    JOIN public._reference141x1 AS client
      ON client._idrref = d._fld4171rref
    JOIN public._reference59 AS contract
      ON contract._idrref = a._fld7578_rrref
    WHERE a._period >= $1::timestamp without time zone
      AND a._period < $2::timestamp without time zone
      AND d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND contract._description NOT LIKE '%ИП%'
      AND contract._description NOT LIKE '%сотрудн%'
      AND d._fld4172 <> d._fld4174
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
)
SELECT visit_date,
       club_id,
       start_hour,
       end_hour,
       sex_code,
       age_years,
       count(*)::bigint AS visit_count,
       sum(club_minutes)::numeric AS club_minutes_total
FROM qualified_visits
GROUP BY visit_date, club_id, start_hour, end_hour, sex_code, age_years;
