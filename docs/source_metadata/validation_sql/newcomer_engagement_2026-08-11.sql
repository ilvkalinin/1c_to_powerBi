-- Source-side read-only controls, 2026-08-11.  See SV-075.
SELECT count(*) AS rows, count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS technical_keys,
       count(*) FILTER (WHERE r._idrref IS NULL) AS contract_orphans,
       count(*) FILTER (WHERE a._fld7576rref<>r._fld681rref) AS client_contract_mismatch,
       sum(a._fld7585) AS quantity_sum
FROM public._accumrg7575 a LEFT JOIN public._reference59 r ON r._idrref=a._fld7578_rrref
WHERE a._period>=DATE '2026-01-01' AND a._period<DATE '2027-01-01';
WITH f AS (SELECT _fld5860rref contract_id,_fld5862 s,_fld5863 e FROM public._inforg5859)
SELECT count(*) AS rows, count(*) FILTER (WHERE e<s) AS reverse_intervals,
       (SELECT count(*) FROM (SELECT contract_id,s,e,count(*) n FROM f GROUP BY 1,2,3 HAVING count(*)>1)d) AS duplicate_intervals FROM f;
