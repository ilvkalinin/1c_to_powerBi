-- REVIEW ONLY — target controls for the BR-032/BR-033 CRM replacement.
-- Bind source COPY totals from one repeatable-read snapshot:
-- $1 shared core, $2 scoped phone rows, $3 final feedback groups,
-- $4 day × club visit metrics.

WITH expected AS (
    SELECT $1::bigint AS core_rows,
           $2::bigint AS phone_rows,
           $3::bigint AS feedback_rows,
           $4::bigint AS club_day_rows
), actual AS (
    SELECT (SELECT count(*) FROM mart.crm_interaction)::bigint AS core_rows,
           (SELECT count(*) FROM mart.crm_interaction_phone)::bigint AS phone_rows,
           (SELECT count(*) FROM mart.feedback_interaction)::bigint AS feedback_rows,
           (SELECT count(*) FROM mart.club_day_metrics)::bigint AS club_day_rows
)
SELECT e.*, a.*,
       (e.core_rows = a.core_rows AND e.phone_rows = a.phone_rows
        AND e.feedback_rows = a.feedback_rows
        AND e.club_day_rows = a.club_day_rows) AS passed
FROM expected e CROSS JOIN actual a;

SELECT count(*)::bigint AS duplicate_core_key_groups
FROM (SELECT interaction_id FROM mart.crm_interaction GROUP BY 1 HAVING count(*) > 1) q;

SELECT count(*)::bigint AS duplicate_phone_key_groups
FROM (
    SELECT interaction_id, phone_reference_id, phone_event_id
    FROM mart.crm_interaction_phone
    GROUP BY 1, 2, 3 HAVING count(*) > 1
) q;

SELECT count(*)::bigint AS duplicate_club_day_key_groups
FROM (SELECT event_date, club_id FROM mart.club_day_metrics GROUP BY 1, 2 HAVING count(*) > 1) q;

SELECT count(*) FILTER (WHERE interaction_id IS NULL OR task_id IS NULL
                         OR created_at IS NULL OR NOT (sales_scope OR guest_scope))
         AS invalid_core_rows
FROM mart.crm_interaction;

SELECT count(*) FILTER (WHERE worked_flag <> (worked_at IS NOT NULL)
                         OR response_minutes IS NOT NULL AND worked_at IS NULL)
         AS invalid_feedback_rows
FROM mart.feedback_interaction;

SELECT count(*)::bigint AS public_select_grants
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
WHERE n.nspname = 'mart'
  AND c.relname IN ('crm_interaction', 'crm_interaction_phone',
                    'feedback_interaction', 'club_day_metrics',
                    'v_sales_interaction', 'v_feedback_interaction', 'v_guest_tour')
  AND a.grantee = 0
  AND a.privilege_type = 'SELECT';
