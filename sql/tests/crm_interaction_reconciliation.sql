-- REVIEW ONLY — target reconciliation for the future CRM implementation.
-- The runner binds source snapshot aggregate values into expected once per run.
WITH expected AS (
    SELECT $1::bigint AS core_rows,
           $2::bigint AS phone_rows,
           $3::bigint AS comment_rows
), actual AS (
    SELECT (SELECT count(*) FROM mart.crm_interaction)::bigint AS core_rows,
           (SELECT count(*) FROM mart.crm_interaction_phone)::bigint AS phone_rows,
           (SELECT count(*) FROM mart.crm_interaction_comment)::bigint AS comment_rows
)
SELECT e.*, a.*,
       (e.core_rows = a.core_rows AND e.phone_rows = a.phone_rows
        AND e.comment_rows = a.comment_rows) AS passed
FROM expected e CROSS JOIN actual a;

SELECT count(*)::bigint AS duplicate_core_key_groups
FROM (
    SELECT interaction_id
    FROM mart.crm_interaction
    GROUP BY interaction_id
    HAVING count(*) > 1
) d;

SELECT count(*)::bigint AS duplicate_phone_key_groups
FROM (
    SELECT interaction_id, phone_reference_id, phone_event_id
    FROM mart.crm_interaction_phone
    GROUP BY 1, 2, 3
    HAVING count(*) > 1
) d;

SELECT count(*)::bigint AS duplicate_comment_key_groups
FROM (
    SELECT interaction_id, comment_id
    FROM mart.crm_interaction_comment
    GROUP BY 1, 2
    HAVING count(*) > 1
) d;

SELECT count(*) FILTER (WHERE interaction_id IS NULL OR task_id IS NULL
                         OR created_at IS NULL OR event_type_id IS NULL)
         AS required_core_null_rows,
       count(*) FILTER (WHERE source_marked OR source_archived)
         AS source_state_rows_preserved
FROM mart.crm_interaction;
