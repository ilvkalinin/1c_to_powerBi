-- $1..$10 are independent source expected values; $11/$12 are the BR-003 horizon.
WITH actual AS (
    SELECT
        count(*)::bigint AS rows_total,
        count(*) FILTER (WHERE activity_kind = 'TRAINING')::bigint AS training_rows,
        count(*) FILTER (WHERE activity_kind = 'DUTY')::bigint AS duty_rows,
        count(*) FILTER (WHERE activity_kind IN ('COUPON_1', 'COUPON_2'))::bigint AS coupon_rows,
        coalesce(sum(duration_minutes) FILTER (WHERE activity_kind = 'TRAINING'), 0)::numeric AS training_minutes,
        coalesce(sum(duration_minutes) FILTER (WHERE activity_kind = 'DUTY'), 0)::numeric AS duty_minutes,
        coalesce(sum(duration_minutes) FILTER (WHERE activity_kind IN ('COUPON_1', 'COUPON_2')), 0)::numeric AS coupon_minutes,
        min(activity_date) AS min_activity_date,
        max(activity_date) AS max_activity_date,
        count(DISTINCT activity_event_key)::bigint AS distinct_keys
    FROM mart.employee_activity_interval
)
SELECT control_id, expected, actual, tolerance,
       CASE WHEN expected IS NOT DISTINCT FROM actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM actual
CROSS JOIN LATERAL (
    VALUES
      ('EAI-R01_ROWS', $1::text, rows_total::text, '0'),
      ('EAI-R02_TRAINING_ROWS', $2::text, training_rows::text, '0'),
      ('EAI-R03_DUTY_ROWS', $3::text, duty_rows::text, '0'),
      ('EAI-R04_COUPON_ROWS', $4::text, coupon_rows::text, '0'),
      ('EAI-R05_TRAINING_MINUTES', $5::text, training_minutes::text, '0'),
      ('EAI-R06_DUTY_MINUTES', $6::text, duty_minutes::text, '0'),
      ('EAI-R07_COUPON_MINUTES', $7::text, coupon_minutes::text, '0'),
      ('EAI-R08_MIN_DATE', $8::text, min_activity_date::text, '0'),
      ('EAI-R09_MAX_DATE', $9::text, max_activity_date::text, '0'),
      ('EAI-R10_DISTINCT_KEY', $10::text, distinct_keys::text, '0'),
      ('EAI-R13_HORIZON', '0', count(*) FILTER (
           WHERE activity_date < $11::date OR activity_date >= $12::date
        )::text, '0'),
      ('EAI-R14_CONTRACT', '0', count(*) FILTER (
           WHERE activity_event_key IS NULL OR club_id IS NULL OR employee_id IS NULL
              OR activity_date IS NULL OR start_at IS NULL OR end_at IS NULL
              OR end_at <= start_at OR duration_minutes < 0
              OR activity_kind NOT IN ('TRAINING', 'DUTY', 'COUPON_1', 'COUPON_2')
              OR payment_kind NOT IN ('Платно', 'Бесплатно', 'Дежурство')
        )::text, '0')
) AS controls(control_id, expected, actual, tolerance);
