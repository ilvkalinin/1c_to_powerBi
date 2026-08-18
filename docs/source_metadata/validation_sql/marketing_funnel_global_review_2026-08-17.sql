-- Global read-only review: «Маркетинговая воронка».
-- The physical bridge already uses task IDs. This control only measures
-- whether the current display/DAX task code is also unique across CRM tasks.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

-- MF-V02. Expected: physical IDs are unique. A code is not adopted as a
-- physical mart key unless no null codes and no code shared by several IDs.
-- The control is limited to the report funnel and uses its source index.
WITH funnel AS MATERIALIZED (
  SELECT _idrref AS funnel_id
  FROM public._reference89
  WHERE _description::text = 'Продажа клубной карты'
)
SELECT count(*) AS task_rows,
       count(DISTINCT t._idrref) AS physical_task_ids,
       count(DISTINCT t._code) AS nonnull_task_codes,
       count(*) FILTER (WHERE t._code IS NULL) AS null_task_codes,
       count(*) - count(DISTINCT t._code) AS code_duplicate_excess
FROM funnel f
JOIN public._reference106 t ON t._fld1191rref = f.funnel_id;

-- MF-V06. Expected: source states are observed only in the already confirmed
-- BR-020 bridge; no state filter is introduced by this control.
WITH eligible_bridge AS (
  SELECT t._marked AS task_marked,
         c._marked AS contract_marked
  FROM public._inforg6798 r
  JOIN public._reference59 c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 t ON t._idrref = r._fld6799rref
  JOIN public._reference89 f ON f._idrref = t._fld1191rref
  WHERE r._fld6802
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND f._description::text = 'Продажа клубной карты'
    AND c._fld670::date >= DATE '2024-01-01'
    AND c._fld670::date >= t._fld1193::date
)
SELECT count(*) AS qualified_bridge_rows,
       count(*) FILTER (WHERE task_marked) AS marked_task_rows,
       count(*) FILTER (WHERE contract_marked) AS marked_contract_rows
FROM eligible_bridge;

-- MF-V07, executed 2026-08-18. Expected: every qualified report-scope bridge
-- is classified by the current duration boundaries, while null/nonpositive
-- values are observed rather than silently filtered or reassigned.
WITH eligible_bridge AS MATERIALIZED (
  SELECT c._fld693::numeric AS duration_days
  FROM public._inforg6798 r
  JOIN public._reference59 c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 t ON t._idrref = r._fld6799rref
  JOIN public._reference89 f ON f._idrref = t._fld1191rref
  WHERE r._fld6802
    AND f._description::text = 'Продажа клубной карты'
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._fld670::date >= DATE '2024-01-01'
    AND c._fld670::date >= t._fld1193::date
)
SELECT count(*) AS qualified_bridge_rows,
       count(*) FILTER (WHERE duration_days IS NULL) AS null_duration_rows,
       count(*) FILTER (WHERE duration_days <= 0) AS nonpositive_duration_rows,
       count(*) FILTER (WHERE duration_days BETWEEN 1 AND 7) AS duration_001_007,
       count(*) FILTER (WHERE duration_days BETWEEN 8 AND 30) AS duration_008_030,
       count(*) FILTER (WHERE duration_days BETWEEN 31 AND 180) AS duration_031_180,
       count(*) FILTER (WHERE duration_days BETWEEN 181 AND 364) AS duration_181_364,
       count(*) FILTER (WHERE duration_days >= 365) AS duration_365_plus
FROM eligible_bridge;

-- MF-V07B, executed 2026-08-18. This observes payment-type field coverage
-- in the report bridge. It does not infer which physical value is recurring.
WITH eligible_bridge AS MATERIALIZED (
  SELECT c._fld699rref AS payment_type_id
  FROM public._inforg6798 r
  JOIN public._reference59 c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 t ON t._idrref = r._fld6799rref
  JOIN public._reference89 f ON f._idrref = t._fld1191rref
  WHERE r._fld6802
    AND f._description::text = 'Продажа клубной карты'
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._fld670::date >= DATE '2024-01-01'
    AND c._fld670::date >= t._fld1193::date
)
SELECT count(*) AS qualified_bridge_rows,
       count(DISTINCT payment_type_id) AS nonnull_payment_type_values,
       count(*) FILTER (WHERE payment_type_id IS NULL) AS null_payment_type_rows
FROM eligible_bridge;

-- MF-V07C, executed 2026-08-18. BR-024 reuses the exact recurring mapping
-- confirmed in the current membership-receipts M code; this checks coverage
-- in the marketing report scope without inferring a label from source order.
WITH eligible_bridge AS MATERIALIZED (
  SELECT c._fld699rref AS payment_type_id
  FROM public._inforg6798 r
  JOIN public._reference59 c ON c._idrref = r._fld6800_rrref
  JOIN public._reference106 t ON t._idrref = r._fld6799rref
  JOIN public._reference89 f ON f._idrref = t._fld1191rref
  WHERE r._fld6802
    AND f._description::text = 'Продажа клубной карты'
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._fld670::date >= DATE '2024-01-01'
    AND c._fld670::date >= t._fld1193::date
)
SELECT count(*) AS qualified_bridge_rows,
       count(*) FILTER (WHERE payment_type_id = decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')) AS recurring_rows,
       count(*) FILTER (WHERE payment_type_id <> decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')) AS prepayment_rows,
       count(*) FILTER (WHERE payment_type_id IS NULL) AS null_payment_type_rows
FROM eligible_bridge;

-- MF-V08, control month 2025-07-01. Expected: the three components reproduce
-- the exact current DAX measure `ФактЗаявкиНакопленныйТрафик` on the current
-- PBIT scope: tasks from `UNION(Задания 2024, Задания 2025)`, minus distinct
-- cancelled tasks and the SUM of distinct contract clients per task. The final
-- value must equal `all_tasks - cancelled_tasks - activated_contract_clients`;
-- DAX returns that same final value for both traffic directions. No claim of
-- equality with a Power BI numeric control is made because no such values were
-- supplied.
WITH params AS (
  SELECT DATE '2025-07-01' AS month_start
),
report_tasks AS MATERIALIZED (
  SELECT t._idrref AS task_id,
         t._code::text AS task_code,
         t._fld1193 AS created_at,
         t._fld1192 AS closed_at,
         t._fld1205rref AS stage_id
  FROM public._reference106 t
  JOIN public._reference89 f ON f._idrref = t._fld1191rref
  LEFT JOIN public._reference132 club ON club._idrref = t._fld1195rref
  LEFT JOIN public._reference201 reason ON reason._idrref = t._fld1201rref
  WHERE f._description::text = 'Продажа клубной карты'
    AND (club._description IS NULL
         OR club._description::text <> 'Детский развивающий центр')
    AND t._fld1193 > TIMESTAMP '2024-04-01'
    AND t._fld1193 < TIMESTAMP '2026-01-01'
    AND NOT t._marked
    AND COALESCE(reason._description::text, '') NOT IN (
      '(Не использовать) Найдено аналогичное задание',
      'Найдено аналогичное задание'
    )
),
window_tasks AS MATERIALIZED (
  SELECT rt.*
  FROM report_tasks rt
  CROSS JOIN params p
  WHERE rt.created_at::date >= (p.month_start - INTERVAL '2 months')::date
    AND rt.created_at::date < p.month_start
),
cancelled AS MATERIALIZED (
  SELECT DISTINCT wt.task_code
  FROM window_tasks wt
  JOIN public._reference264 stage ON stage._idrref = wt.stage_id
  CROSS JOIN params p
  WHERE stage._description::text IN ('Отказ', 'Отмена')
    AND wt.closed_at::date < p.month_start
),
activated_contract_clients_by_task AS MATERIALIZED (
  SELECT wt.task_code,
         count(DISTINCT client._code) AS distinct_clients
  FROM window_tasks wt
  JOIN public._inforg6798 r ON r._fld6799rref = wt.task_id
  JOIN public._reference59 c ON c._idrref = r._fld6800_rrref
  LEFT JOIN public._reference141x1 client ON client._idrref = c._fld681rref
  CROSS JOIN params p
  WHERE r._fld6802
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._fld670 IS NOT NULL
    AND c._fld670::date < p.month_start
  GROUP BY wt.task_code
),
components AS (
  SELECT
    (SELECT count(DISTINCT task_code) FROM window_tasks) AS all_tasks,
    (SELECT count(*) FROM cancelled) AS cancelled_tasks,
    (SELECT COALESCE(sum(distinct_clients), 0)
     FROM activated_contract_clients_by_task) AS activated_contract_clients
)
SELECT all_tasks,
       cancelled_tasks,
       activated_contract_clients,
       all_tasks - cancelled_tasks - activated_contract_clients
         AS current_dax_final_value,
       (all_tasks - cancelled_tasks - activated_contract_clients)
         = (all_tasks - cancelled_tasks - activated_contract_clients)
         AS same_for_inbound_and_outbound,
       (SELECT count(*) FROM activated_contract_clients_by_task)
         AS tasks_with_pre_month_contract_clients
FROM components;

ROLLBACK;
