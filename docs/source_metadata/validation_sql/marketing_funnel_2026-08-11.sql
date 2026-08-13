-- SV-080, bounded MF-V03: current read-only task-to-contract bridge.
WITH b AS MATERIALIZED (SELECT r._fld6799rref task_id,r._fld6800_rrref contract_id FROM public._inforg6798 r JOIN public._reference59 c ON c._idrref=r._fld6800_rrref JOIN public._reference106 t ON t._idrref=r._fld6799rref JOIN public._reference89 f ON f._idrref=t._fld1191rref WHERE r._fld6802 AND c._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex') AND c._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex') AND f._description='Продажа клубной карты' ORDER BY r._fld6799rref LIMIT 100),g AS (SELECT task_id,count(DISTINCT contract_id)n FROM b GROUP BY 1) SELECT (SELECT count(*) FROM b) bridge_rows,count(*) tasks,count(*) FILTER(WHERE n>1) multi_contract_tasks,coalesce(sum(n) FILTER(WHERE n>1),0) contracts_in_multi,max(n) max_contracts_per_task FROM g;

-- MF-V03E, 2026-08-13. User-requested concrete code example. Execute only in
-- BEGIN READ ONLY as gymdb_readonly. Expected: one task code with more than
-- one distinct eligible contract code; no PII fields are selected.
WITH bridge AS (
  SELECT t._code::text AS task_code, c._code::text AS contract_code
  FROM public._inforg6798 AS r
  JOIN public._reference59 AS c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 AS t ON t._idrref = r._fld6799rref
  JOIN public._reference89 AS f ON f._idrref = t._fld1191rref
  WHERE r._fld6802 = true
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND f._description = 'Продажа клубной карты'
)
SELECT task_code,
       string_agg(DISTINCT contract_code, ', ' ORDER BY contract_code)
         AS contract_codes
FROM bridge
GROUP BY task_code
HAVING count(DISTINCT contract_code) > 1
ORDER BY task_code
LIMIT 1;
