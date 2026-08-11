-- SV-079, bounded read-only cohort control.
WITH e AS MATERIALIZED (
  SELECT _idrref AS contract_id,_fld681rref AS client_id,_fld671::date AS start_date
  FROM public._reference59
  WHERE _fld671>=DATE '2026-01-01' AND _fld671<DATE '2026-04-01'
    AND _fld671<_fld672 AND _fld671<CURRENT_DATE AND _fld693>6 AND _fld681rref IS NOT NULL
  ORDER BY _idrref LIMIT 100
), g AS (SELECT client_id,start_date,count(*) AS n FROM e GROUP BY 1,2)
SELECT (SELECT count(*) FROM e) AS contract_rows,count(*) AS cohort_rows,
       count(*) FILTER (WHERE n>1) AS multi_contract_cohorts,
       coalesce(sum(n) FILTER (WHERE n>1),0) AS contracts_in_multi,max(n) AS max_contracts_per_cohort
FROM g;
