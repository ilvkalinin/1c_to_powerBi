-- REVIEW ONLY — Stage-3 source-to-target reconciliation for marketing funnel.
-- Execute inside the target transaction after both binary COPY operations.
-- Bind $1 = source task COPY row count and $2 = source candidate-contract COPY
-- row count, both captured from the same REPEATABLE READ source snapshot.

-- MF-R01: transport completeness. Expected: passed = true.
WITH expected AS (
    SELECT $1::bigint AS task_rows, $2::bigint AS contract_rows
), actual AS (
    SELECT (SELECT count(*)::bigint FROM mart.marketing_funnel_task) AS task_rows,
           (SELECT count(*)::bigint FROM mart.marketing_funnel_task_contract) AS contract_rows
)
SELECT e.*, a.*,
       (e.task_rows = a.task_rows AND e.contract_rows = a.contract_rows) AS passed
FROM expected AS e CROSS JOIN actual AS a;

-- MF-R02: logical keys. Expected: all three values = 0.
SELECT
  (SELECT count(*)::bigint
   FROM (SELECT task_id FROM mart.marketing_funnel_task GROUP BY 1 HAVING count(*) > 1) AS q) AS duplicate_task_keys,
  (SELECT count(*)::bigint
   FROM (SELECT task_id, contract_id FROM mart.marketing_funnel_task_contract
         GROUP BY 1, 2 HAVING count(*) > 1) AS q) AS duplicate_task_contract_keys,
  (SELECT count(*)::bigint
   FROM mart.marketing_funnel_task_contract AS tc
   LEFT JOIN mart.marketing_funnel_task AS t ON t.task_id = tc.task_id
   WHERE t.task_id IS NULL) AS orphan_contract_rows;

-- MF-R03: required fields and preserved BR-020 semantics. Expected: all = 0.
SELECT
  (SELECT count(*)::bigint FROM mart.marketing_funnel_task
   WHERE task_id IS NULL OR task_code IS NULL OR task_created_at IS NULL
      OR task_date IS NULL OR task_date <> task_created_at::date
      OR funnel_id IS NULL OR funnel_name IS NULL OR task_count <> 1) AS invalid_task_rows,
  (SELECT count(*)::bigint FROM mart.marketing_funnel_task_contract
   WHERE task_id IS NULL OR contract_id IS NULL OR activation_date IS NULL
      OR is_conversion_qualified IS NULL
      OR contract_count <> CASE WHEN is_conversion_qualified THEN 1 ELSE 0 END) AS invalid_contract_rows,
  (SELECT count(*)::bigint
   FROM mart.marketing_funnel_task AS t
   JOIN mart.marketing_funnel_task_contract AS tc ON tc.task_id = t.task_id
   WHERE tc.is_conversion_qualified
     AND tc.activation_date < t.task_date) AS br020_violations;

-- MF-R04: BR-003 and source history guard. Expected: all = 0.
-- Bind the exact run horizon to $3/$4 only when inspecting this statement;
-- at 2026-08-24 they are DATE '2025-01-01' and DATE '2027-01-01'.
SELECT
  (SELECT count(*)::bigint FROM mart.marketing_funnel_task
   WHERE task_date < $3::date OR task_date >= $4::date)
    AS task_outside_br003_horizon,
  (SELECT count(*)::bigint FROM mart.marketing_funnel_task_contract
   WHERE activation_date < DATE '2024-01-01')
    AS contract_before_current_history;

-- MF-R05: independent current-PBIT control at 2025-07-01.
-- Evidence fixed before implementation: 66,404 - 27,319 - 15,221 = 23,864.
-- Expected: all_tasks=66404, cancelled_tasks=27319,
-- activated_contract_clients=15221, current_dax_final_value=23864, passed=true.
WITH params AS (
    SELECT DATE '2025-07-01' AS month_start
), report_tasks AS MATERIALIZED (
    SELECT task_id, task_code, task_created_at, closed_at, funnel_stage_name
    FROM mart.marketing_funnel_task
    WHERE task_created_at > TIMESTAMP '2024-04-01'
      AND task_created_at < TIMESTAMP '2026-01-01'
), window_tasks AS MATERIALIZED (
    SELECT rt.*
    FROM report_tasks AS rt CROSS JOIN params AS p
    WHERE rt.task_created_at::date >= (p.month_start - INTERVAL '2 months')::date
      AND rt.task_created_at::date < p.month_start
), cancelled AS MATERIALIZED (
    SELECT DISTINCT wt.task_code
    FROM window_tasks AS wt CROSS JOIN params AS p
    WHERE wt.funnel_stage_name IN ('Отказ', 'Отмена')
      AND wt.closed_at::date < p.month_start
), activated_contract_clients_by_task AS MATERIALIZED (
    SELECT wt.task_code,
           count(DISTINCT tc.contract_client_code) AS distinct_clients
    FROM window_tasks AS wt
    JOIN mart.marketing_funnel_task_contract AS tc ON tc.task_id = wt.task_id
    CROSS JOIN params AS p
    WHERE tc.activation_date < p.month_start
    GROUP BY wt.task_code
), components AS (
    SELECT (SELECT count(DISTINCT task_code) FROM window_tasks) AS all_tasks,
           (SELECT count(*) FROM cancelled) AS cancelled_tasks,
           (SELECT coalesce(sum(distinct_clients), 0)
            FROM activated_contract_clients_by_task) AS activated_contract_clients
)
SELECT *,
       all_tasks - cancelled_tasks - activated_contract_clients AS current_dax_final_value,
       (all_tasks = 66404 AND cancelled_tasks = 27319
        AND activated_contract_clients = 15221
        AND all_tasks - cancelled_tasks - activated_contract_clients = 23864) AS passed
FROM components;

-- MF-R06: target access boundary. Expected: 0.
SELECT count(*)::bigint AS public_select_grants
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS a
WHERE n.nspname = 'mart'
  AND c.relname IN ('marketing_funnel_task', 'marketing_funnel_task_contract')
  AND a.grantee = 0
  AND a.privilege_type = 'SELECT';
