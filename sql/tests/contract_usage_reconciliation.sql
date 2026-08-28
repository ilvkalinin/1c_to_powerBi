-- Target reconciliation for mart.contract_usage.
-- $1..$4 are independently captured CU-S03 values: stage rows, visit sum,
-- min start date and max end date.  It runs inside the target transaction
-- after COPY and before COMMIT.
WITH stage AS MATERIALIZED (
    SELECT count(*)::bigint AS rows_total,
           coalesce(sum(visit_count), 0)::bigint AS visit_count_sum,
           min(membership_start_date) AS min_membership_start_date,
           max(membership_end_date) AS max_membership_end_date,
           count(*) FILTER (
               WHERE contract_id IS NULL OR contract_code IS NULL
                  OR membership_start_date IS NULL OR membership_end_date IS NULL
                  OR contract_end_month IS NULL OR active_calendar_months < 1
                  OR visit_count <= 0
                  OR membership_end_date < membership_start_date
                  OR contract_end_month <> date_trunc('month', membership_end_date)::date
           )::bigint AS stage_contract_violations
    FROM _contract_usage_stage
), matched_stage AS MATERIALIZED (
    SELECT s.contract_id,
           t.contract_id AS target_contract_id,
           ROW(s.contract_code, s.membership_start_date, s.membership_end_date,
               s.contract_end_month, s.membership_term_days, s.active_calendar_months,
               s.visit_count, s.usage_rate, s.average_monthly_visits)
             IS NOT DISTINCT FROM
           ROW(t.contract_code, t.membership_start_date, t.membership_end_date,
               t.contract_end_month, t.membership_term_days, t.active_calendar_months,
               t.visit_count, t.usage_rate, t.average_monthly_visits) AS matches_target
    FROM _contract_usage_stage AS s
    LEFT JOIN mart.contract_usage AS t ON t.contract_id = s.contract_id
), target_contract_violations AS MATERIALIZED (
    SELECT count(*)::bigint AS violations
    FROM mart.contract_usage
    WHERE contract_id IS NULL OR contract_code IS NULL
       OR membership_start_date IS NULL OR membership_end_date IS NULL
       OR contract_end_month IS NULL OR active_calendar_months < 1
       OR visit_count <= 0 OR membership_end_date < membership_start_date
       OR contract_end_month <> date_trunc('month', membership_end_date)::date
)
SELECT control_id, expected, actual, tolerance,
       CASE WHEN expected IS NOT DISTINCT FROM actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM stage
CROSS JOIN target_contract_violations
CROSS JOIN LATERAL (
    VALUES
      ('CU-R01_STAGE_ROWS', $1::text, rows_total::text, '0'),
      ('CU-R02_STAGE_VISIT_SUM', $2::text, visit_count_sum::text, '0'),
      ('CU-R03_STAGE_MIN_START', $3::text, min_membership_start_date::text, '0'),
      ('CU-R04_STAGE_MAX_END', $4::text, max_membership_end_date::text, '0'),
      ('CU-R05_STAGE_TO_TARGET', '0',
       (SELECT count(*) FILTER (WHERE target_contract_id IS NULL OR NOT matches_target)::text
          FROM matched_stage), '0'),
      ('CU-R06_EXCESS_TARGET', '0',
       (SELECT count(*)::text
          FROM mart.contract_usage AS t
          LEFT JOIN _contract_usage_stage AS s ON s.contract_id = t.contract_id
         WHERE s.contract_id IS NULL), '0'),
      ('CU-R07_STAGE_CONTRACT', '0', stage_contract_violations::text, '0'),
      ('CU-R08_TARGET_CONTRACT', '0', violations::text, '0')
) AS controls(control_id, expected, actual, tolerance);
