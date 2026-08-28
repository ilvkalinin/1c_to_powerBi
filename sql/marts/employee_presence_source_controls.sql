-- Independent source expected controls for future physical admission; $1/$2 are [start,end).
-- This is deliberately an aggregate control path, not either COPY extract.
WITH service AS MATERIALIZED (
 SELECT c._idrref FROM public._reference163 c JOIN public._reference163 p ON p._idrref=c._parentidrref WHERE p._description::text='Служебная'
), ec AS MATERIALIZED (
 SELECT _fld2504rref client_id, count(*) employee_count, min(_idrref) employee_id FROM public._reference225 WHERE _fld2504rref IS NOT NULL GROUP BY _fld2504rref
), raw AS MATERIALIZED (
 SELECT a._period::date presence_date, a._fld7577rref club_ref, ec.employee_count, ec.employee_id,
   CASE WHEN d._fld4174=TIMESTAMP '0001-01-01 00:00:00' OR d._fld4174>date_trunc('day',d._fld4172)+interval '1 day'-interval '1 microsecond'
        THEN date_trunc('day',d._fld4172)+interval '1 day'-interval '1 microsecond' ELSE d._fld4174 END - d._fld4172 duration
 FROM public._accumrg7575 a JOIN public._document325 d ON d._idrref=a._recorderrref
 JOIN public._reference132 club ON club._idrref=a._fld7577rref JOIN public._reference59 card ON card._idrref=a._fld7578_rrref
 JOIN service s ON s._idrref=card._fld685rref LEFT JOIN ec ON ec.client_id=a._fld7576rref
 WHERE d._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex') AND club._description::text NOT IN ('Детский развивающий центр','Управляющая компания')
   AND a._period >= $1::date AND a._period < $2::date
), personal AS (SELECT presence_date,club_ref,employee_id,sum(extract(epoch FROM duration)/60.0)::numeric minutes FROM raw WHERE employee_count=1 GROUP BY 1,2,3),
unattributed AS (SELECT presence_date,club_ref,CASE WHEN employee_count IS NULL THEN 'NO_EMPLOYEE' ELSE 'MULTIPLE_EMPLOYEES' END status,sum(extract(epoch FROM duration)/60.0)::numeric minutes FROM raw WHERE employee_count IS NULL OR employee_count>1 GROUP BY 1,2,3)
SELECT (SELECT count(*) FROM personal)::bigint personal_rows,(SELECT coalesce(sum(minutes),0) FROM personal)::numeric personal_minutes,
 (SELECT min(presence_date) FROM personal) personal_min_date,(SELECT max(presence_date) FROM personal) personal_max_date,
 (SELECT count(*) FROM unattributed)::bigint unattributed_rows,(SELECT coalesce(sum(minutes),0) FROM unattributed)::numeric unattributed_minutes,
 (SELECT min(presence_date) FROM unattributed) unattributed_min_date,(SELECT max(presence_date) FROM unattributed) unattributed_max_date,
 (SELECT count(*) FROM raw WHERE employee_count IS NULL)::bigint no_employee_source_rows,
 (SELECT count(*) FROM raw WHERE employee_count>1)::bigint multi_employee_source_rows;
