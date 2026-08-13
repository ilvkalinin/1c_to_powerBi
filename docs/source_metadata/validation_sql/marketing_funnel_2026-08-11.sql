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

-- MF-V03F, 2026-08-13. Reverse-direction user-requested example. This is a
-- different control from MF-V03/MF-V03E: it groups the same current bridge by
-- contract to prove one eligible contract linked to several task codes.
WITH bridge AS (
  SELECT c._code::text AS contract_code, t._code::text AS task_code
  FROM public._inforg6798 AS r
  JOIN public._reference59 AS c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 AS t ON t._idrref = r._fld6799rref
  JOIN public._reference89 AS f ON f._idrref = t._fld1191rref
  WHERE r._fld6802 = true
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND f._description = 'Продажа клубной карты'
)
SELECT contract_code,
       string_agg(DISTINCT task_code, ', ' ORDER BY task_code) AS task_codes
FROM bridge
GROUP BY contract_code
HAVING count(DISTINCT task_code) > 1
ORDER BY contract_code
LIMIT 1;

-- MF-V03G, 2026-08-13. Temporal-eligibility check after the explicit
-- user rule: an activated contract counts for conversion only when its
-- activation date is not earlier than the CRM task creation date. Current
-- report history also starts at 2024-01-01. Expected: the two known links of
-- contract code 0000302905 pass neither temporal qualification because its
-- activation is in 2017 and both linked tasks are in 2025.
WITH known_pair AS (
  SELECT c._code::text AS contract_code,
         c._fld670::date AS activation_date,
         t._code::text AS task_code,
         t._fld1193::date AS task_created_date
  FROM public._inforg6798 AS r
  JOIN public._reference59 AS c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 AS t ON t._idrref = r._fld6799rref
  WHERE c._code::text = '0000302905'
    AND t._code::text IN ('008259075', '008854940')
)
SELECT count(*) AS known_links,
       count(*) FILTER (
         WHERE activation_date >= DATE '2024-01-01'
           AND activation_date >= task_created_date
       ) AS report_eligible_links
FROM known_pair;

-- MF-V03H, 2026-08-13. Cardinality observation of the temporally eligible
-- source bridge after the current contract filters.
-- Expected: every included link satisfies both temporal predicates; the
-- observed task/contract multiplicity is recorded without deduplication.
WITH eligible_bridge AS (
  SELECT r._fld6799rref AS task_id,
         r._fld6800_rrref AS contract_id
  FROM public._inforg6798 AS r
  JOIN public._reference59 AS c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 AS t ON t._idrref = r._fld6799rref
  JOIN public._reference89 AS f ON f._idrref = t._fld1191rref
  WHERE r._fld6802 = true
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND f._description = 'Продажа клубной карты'
    AND c._fld670::date >= DATE '2024-01-01'
    AND c._fld670::date >= t._fld1193::date
), per_task AS (
  SELECT task_id, count(DISTINCT contract_id) AS contracts_per_task
  FROM eligible_bridge GROUP BY 1
), per_contract AS (
  SELECT contract_id, count(DISTINCT task_id) AS tasks_per_contract
  FROM eligible_bridge GROUP BY 1
)
SELECT (SELECT count(*) FROM eligible_bridge) AS bridge_rows,
       (SELECT count(*) FROM per_task) AS tasks,
       (SELECT count(*) FILTER (WHERE contracts_per_task > 1) FROM per_task)
         AS multi_contract_tasks,
       (SELECT count(*) FROM per_contract) AS contracts,
       (SELECT count(*) FILTER (WHERE tasks_per_contract > 1) FROM per_contract)
         AS multi_task_contracts;
