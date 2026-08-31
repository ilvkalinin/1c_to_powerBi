-- Read-only source-diff control for the separate incremental runner of
-- mart.client_base_daily. Bind $1 = inclusive horizon start, $2 = exclusive
-- horizon end. The embedded fact is the reviewed exact source aggregate; no
-- client or membership identifier leaves it.
--
-- A date is eligible for replacement only if either its row count or both
-- deterministic digests differ from the persisted target. Before COMMIT the
-- runner still performs exact row-level reconciliation for every selected
-- date, so these digests are a change detector, not an acceptance control.
WITH fact AS (
    /*__CLIENT_BASE_DAILY_FACT__*/
)
SELECT report_date,
       count(*)::bigint AS row_count,
       md5(string_agg(
           jsonb_build_array(
               scope_level, report_date, club_id, age_years,
               age_group, gender, client_count
           )::text,
           E'\n'
           ORDER BY scope_level, club_id NULLS FIRST, age_years NULLS FIRST,
                    age_group, gender, client_count
       )) AS digest_v1,
       md5(string_agg(
           jsonb_build_array(
               client_count, gender, age_group, age_years,
               club_id, report_date, scope_level
           )::text,
           E'\x1f'
           ORDER BY client_count, gender, age_group, age_years NULLS FIRST,
                    club_id NULLS FIRST, scope_level
       )) AS digest_v2
FROM fact
GROUP BY report_date
ORDER BY report_date;
