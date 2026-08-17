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

ROLLBACK;
