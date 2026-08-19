-- Read-only acceptance after an approved initial load of mart.client_base_daily.
-- Source expected controls are captured in the same repeatable-read source
-- snapshot by scripts/load_client_base_daily.py. Bind $1/$2 to BR-003 and
-- compare each scope/day total with that captured source result at tolerance 0.

-- CBD-REC-001: target key and contract. Expected duplicate_keys,
-- contract_violations and rows_outside_horizon = 0.
SELECT
    count(*)::bigint AS target_rows,
    (
        SELECT coalesce(sum(key_rows - 1), 0)::bigint
        FROM (
            SELECT count(*)::bigint AS key_rows
            FROM mart.client_base_daily
            GROUP BY scope_level, report_date, club_id, age_years, age_group, gender
            HAVING count(*) > 1
        ) AS duplicate_key
    ) AS duplicate_keys,
    count(*) FILTER (
        WHERE (scope_level = 'club' AND club_id IS NULL)
           OR (scope_level = 'network' AND club_id IS NOT NULL)
           OR scope_level NOT IN ('club', 'network')
           OR age_group IS NULL
           OR gender NOT IN ('Женский', 'Мужской', 'Не указано')
           OR client_count IS NULL OR client_count <= 0
           OR NOT (
               (age_years IS NULL AND age_group = 'Не указано')
               OR (age_years < 14 AND age_group = 'Дети')
               OR (age_years BETWEEN 14 AND 17 AND age_group = 'Юниоры')
               OR (age_years >= 18 AND age_group = 'Взрослые')
           )
    ) AS contract_violations,
    count(*) FILTER (
        WHERE report_date < $1::date OR report_date >= $2::date
    ) AS rows_outside_horizon
FROM mart.client_base_daily;

-- CBD-REC-002: target daily totals by scope. Expected one positive total for
-- every date and scope; each value equals the independently captured source
-- control from client_base_daily_source_controls.sql exactly.
SELECT report_date,
       scope_level,
       sum(client_count)::bigint AS client_count
FROM mart.client_base_daily
WHERE report_date >= $1::date
  AND report_date < $2::date
GROUP BY report_date, scope_level
ORDER BY report_date, scope_level;
