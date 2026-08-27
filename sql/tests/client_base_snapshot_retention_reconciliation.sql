-- Post-commit target contract checks for the two physical client-base facts.
-- Bind $1/$2 to the exact BR-003 output horizon. Source-to-target equality is
-- checked by scripts/load_client_base_snapshot_retention.py in the same run.
WITH horizon AS (
    SELECT $1::date AS horizon_start, $2::date AS horizon_end
), checks AS (
    SELECT 'snapshot_duplicate_key'::text AS control_id, count(*)::bigint AS deviations
    FROM (
        SELECT 1
        FROM mart.client_base_snapshot
        GROUP BY scope_level, report_date, club_id, age_years, age_group, gender,
                 membership_tenure, activity_bucket
        HAVING count(*) > 1
    ) AS invalid
    UNION ALL
    SELECT 'snapshot_contract_or_horizon', count(*)::bigint
    FROM mart.client_base_snapshot AS s CROSS JOIN horizon AS h
    WHERE s.report_date < h.horizon_start OR s.report_date >= h.horizon_end
       OR s.client_count <= 0
       OR (s.scope_level = 'club' AND s.club_id IS NULL)
       OR (s.scope_level = 'network' AND s.club_id IS NOT NULL)
       OR s.scope_level NOT IN ('club', 'network')
       OR NOT (s.age_group = 'Дети'
               OR (s.age_years IS NULL AND s.age_group = 'Не указано')
               OR (s.age_years BETWEEN 14 AND 17 AND s.age_group = 'Юниоры')
               OR (s.age_years >= 18 AND s.age_group = 'Взрослые'))
    UNION ALL
    SELECT 'retention_duplicate_key', count(*)::bigint
    FROM (
        SELECT 1
        FROM mart.client_base_retention
        GROUP BY scope_level, report_date, comparison_type, comparison_date,
                 baseline_club_id, current_age_years, current_age_group,
                 current_gender, current_membership_tenure
        HAVING count(*) > 1
    ) AS invalid
    UNION ALL
    SELECT 'retention_contract_or_horizon', count(*)::bigint
    FROM mart.client_base_retention AS r CROSS JOIN horizon AS h
    WHERE r.report_date < h.horizon_start OR r.report_date >= h.horizon_end
       OR r.comparison_type NOT IN ('year_start', 'previous_year')
       OR r.comparison_date > r.report_date
       OR r.baseline_client_count <= 0
       OR r.retained_client_count < 0
       OR r.retained_client_count > r.baseline_client_count
       OR (r.scope_level = 'club' AND r.baseline_club_id IS NULL)
       OR (r.scope_level = 'network' AND r.baseline_club_id IS NOT NULL)
       OR r.scope_level NOT IN ('club', 'network')
       OR NOT (r.current_age_group = 'Дети'
               OR (r.current_age_years IS NULL AND r.current_age_group = 'Не указано')
               OR (r.current_age_years BETWEEN 14 AND 17 AND r.current_age_group = 'Юниоры')
               OR (r.current_age_years >= 18 AND r.current_age_group = 'Взрослые'))
)
SELECT control_id, deviations, 0::bigint AS tolerance,
       CASE WHEN deviations = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY control_id;
