-- Target reconciliation for mart.fitness_funnel_client_start.
-- $1..$3 are independently captured FF-S03 values: candidate rows, minimum
-- start date and maximum start date.  It runs inside the target transaction
-- after COPY and before COMMIT.
WITH stage AS MATERIALIZED (
    SELECT count(*)::bigint AS rows_total,
           min(membership_start_date) AS min_membership_start_date,
           max(membership_start_date) AS max_membership_start_date,
           count(*) FILTER (
               WHERE client_key IS NULL OR membership_start_date IS NULL
                  OR access_club_id IS NULL OR tenure_type IS NULL
                  OR client_count <> 1
                  OR tenure_type NOT IN ('New', 'Ex', 'Renew')
           )::bigint AS stage_contract_violations
    FROM _fitness_funnel_client_start_stage
), matched_stage AS MATERIALIZED (
    SELECT s.client_key, s.membership_start_date,
           t.client_key AS target_client_key,
           ROW(s.access_club_id, s.tenure_type, s.client_count) IS NOT DISTINCT FROM
           ROW(t.access_club_id, t.tenure_type, t.client_count) AS matches_target
    FROM _fitness_funnel_client_start_stage AS s
    LEFT JOIN mart.fitness_funnel_client_start AS t
      ON t.client_key = s.client_key
     AND t.membership_start_date = s.membership_start_date
), target_contract_violations AS MATERIALIZED (
    SELECT count(*)::bigint AS violations
    FROM mart.fitness_funnel_client_start
    WHERE client_key IS NULL OR membership_start_date IS NULL
       OR access_club_id IS NULL OR tenure_type IS NULL
       OR client_count <> 1
       OR tenure_type NOT IN ('New', 'Ex', 'Renew')
)
SELECT control_id, expected, actual, tolerance,
       CASE WHEN expected IS NOT DISTINCT FROM actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM stage
CROSS JOIN target_contract_violations
CROSS JOIN LATERAL (
    VALUES
      ('FF-R01_STAGE_ROWS', $1::text, rows_total::text, '0'),
      ('FF-R02_STAGE_MIN_START', $2::text, min_membership_start_date::text, '0'),
      ('FF-R03_STAGE_MAX_START', $3::text, max_membership_start_date::text, '0'),
      ('FF-R04_STAGE_TO_TARGET', '0',
       (SELECT count(*) FILTER (WHERE target_client_key IS NULL OR NOT matches_target)::text
          FROM matched_stage), '0'),
      ('FF-R05_EXCESS_TARGET', '0',
       (SELECT count(*)::text
          FROM mart.fitness_funnel_client_start AS t
          LEFT JOIN _fitness_funnel_client_start_stage AS s
            ON s.client_key = t.client_key
           AND s.membership_start_date = t.membership_start_date
         WHERE s.client_key IS NULL), '0'),
      ('FF-R06_STAGE_CONTRACT', '0', stage_contract_violations::text, '0'),
      ('FF-R07_TARGET_CONTRACT', '0', violations::text, '0')
) AS controls(control_id, expected, actual, tolerance);
