-- Read-only persisted-target counterpart of
-- client_base_daily_incremental_source_fingerprint.sql. Bind $1 = inclusive
-- horizon start, $2 = exclusive horizon end. Its canonical row encoding and
-- ordering must remain identical to the source control.
WITH fact AS (
    SELECT scope_level,
           report_date,
           club_id,
           age_years,
           age_group,
           gender,
           client_count
    FROM mart.client_base_daily
    WHERE report_date >= $1::date
      AND report_date < $2::date
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
