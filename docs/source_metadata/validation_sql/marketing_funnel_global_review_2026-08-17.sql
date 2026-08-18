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

ROLLBACK;
