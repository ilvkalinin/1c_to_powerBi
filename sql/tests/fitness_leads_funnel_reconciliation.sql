-- REVIEWED SOURCE-TO-TARGET reconciliation for «Воронка лиды фитнес».
-- Execute inside the target transaction after both binary COPY operations.
-- $1 = source task COPY count; $2 = source task-service COPY count;
-- $3/$4 = exact BR-003 task horizon; $5—$8 are the exact current-PBIT
-- controls calculated inside the same source REPEATABLE READ snapshot.

-- FL-R01: atomic transport completeness. Expected: passed = true.
WITH expected AS (
    SELECT $1::bigint AS task_rows, $2::bigint AS service_rows
), actual AS (
    SELECT (SELECT count(*)::bigint FROM mart.fitness_leads_funnel_task) AS task_rows,
           (SELECT count(*)::bigint FROM mart.fitness_leads_funnel_task_service) AS service_rows
)
SELECT e.*, a.*,
       (e.task_rows = a.task_rows AND e.service_rows = a.service_rows) AS passed
FROM expected AS e CROSS JOIN actual AS a;

-- FL-R02: task and bridge keys plus referential integrity. Expected: all = 0.
SELECT
  (SELECT count(*)::bigint
   FROM (SELECT task_id FROM mart.fitness_leads_funnel_task GROUP BY 1 HAVING count(*) > 1) AS q)
    AS duplicate_task_keys,
  (SELECT count(*)::bigint
   FROM (SELECT task_id, service_name, service_source
         FROM mart.fitness_leads_funnel_task_service
         GROUP BY 1, 2, 3 HAVING count(*) > 1) AS q)
    AS duplicate_task_service_keys,
  (SELECT count(*)::bigint
   FROM mart.fitness_leads_funnel_task_service AS s
   LEFT JOIN mart.fitness_leads_funnel_task AS t ON t.task_id = s.task_id
   WHERE t.task_id IS NULL) AS orphan_service_rows;

-- FL-R03: fixed fact invariants and current outcome semantics. Expected: all = 0.
SELECT
  (SELECT count(*)::bigint
   FROM mart.fitness_leads_funnel_task
   WHERE task_id IS NULL OR task_code IS NULL OR task_created_at IS NULL
      OR task_date IS NULL OR task_date <> task_created_at::date
      OR closed_at IS NULL OR forced_closed_at IS NULL
      OR funnel_id IS NULL OR funnel_name IS NULL OR parent_campaign_name IS NULL
      OR has_booking IS NULL OR has_paid_training_45d IS NULL OR task_count <> 1)
    AS invalid_task_rows,
  (SELECT count(*)::bigint
   FROM mart.fitness_leads_funnel_task
   WHERE has_paid_training_45d <> (coalesce(training_count, 0) > 0))
    AS inconsistent_paid_training_flags,
  (SELECT count(*)::bigint
   FROM mart.fitness_leads_funnel_task_service
   WHERE task_id IS NULL OR service_name IS NULL OR service_name = ''
      OR service_source NOT IN ('DIRECT_CURRENT', 'FALLBACK_EARLIEST_DAX_MIN'))
    AS invalid_service_rows;

-- FL-R04: BR-003 and preserved bridge behaviour. Expected: all = 0.
SELECT
  (SELECT count(*)::bigint
   FROM mart.fitness_leads_funnel_task
   WHERE task_date < $3::date OR task_date >= $4::date)
    AS task_outside_br003_horizon,
  (SELECT count(*)::bigint
   FROM mart.fitness_leads_funnel_task_service AS s
   JOIN mart.fitness_leads_funnel_task AS t ON t.task_id = s.task_id
   WHERE s.service_source = 'DIRECT_CURRENT'
     AND s.service_date IS DISTINCT FROM t.closed_at::date)
    AS direct_service_date_mismatch,
  (SELECT count(*)::bigint
   FROM mart.fitness_leads_funnel_task_service AS fallback
   WHERE fallback.service_source = 'FALLBACK_EARLIEST_DAX_MIN'
     AND EXISTS (
         SELECT 1
         FROM mart.fitness_leads_funnel_task_service AS direct
         WHERE direct.task_id = fallback.task_id
           AND direct.service_source = 'DIRECT_CURRENT'
     ))
    AS fallback_with_direct_service;

-- FL-R05: current-PBIT controls from the same immutable source snapshot as
-- the binary COPY.  The documented Stage-2 baseline is retained in execution
-- evidence; mutable source data is never compared across snapshots.
WITH expected AS (
    SELECT $5::bigint AS tasks,
           $6::bigint AS stage_booking_tasks,
           $7::bigint AS positive_training_tasks,
           $8::bigint AS training_count_sum
), actual AS (
    SELECT count(*)::bigint AS tasks,
           count(*) FILTER (WHERE has_booking)::bigint AS stage_booking_tasks,
           count(*) FILTER (WHERE has_paid_training_45d)::bigint AS positive_training_tasks,
           coalesce(sum(training_count), 0)::bigint AS training_count_sum
    FROM mart.fitness_leads_funnel_task
)
SELECT e.*, a.*,
       (e.tasks = a.tasks
        AND e.stage_booking_tasks = a.stage_booking_tasks
        AND e.positive_training_tasks = a.positive_training_tasks
        AND e.training_count_sum = a.training_count_sum) AS passed
FROM expected AS e CROSS JOIN actual AS a;

-- FL-R06: target access boundary. Expected: 0.
SELECT count(*)::bigint AS public_select_grants
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS a
WHERE n.nspname = 'mart'
  AND c.relname IN ('fitness_leads_funnel_task', 'fitness_leads_funnel_task_service')
  AND a.grantee = 0
  AND a.privilege_type = 'SELECT';
