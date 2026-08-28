-- Planned in-transaction reconciliation for mart.employee_presence_day.
-- $1..$4 are independent source expected values; $5/$6 are [start,end).
WITH target AS (
  SELECT count(*)::bigint AS rows,
         coalesce(sum(presence_minutes), 0)::numeric AS minutes,
         min(presence_date) AS min_date,
         max(presence_date) AS max_date,
         count(*) FILTER (
           WHERE presence_date < $5::date OR presence_date >= $6::date
              OR club_id IS NULL OR employee_id IS NULL OR presence_minutes < 0
         ) AS contract_violations
  FROM mart.employee_presence_day
)
SELECT id, expected, actual,
       CASE WHEN expected IS NOT DISTINCT FROM actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM target
CROSS JOIN LATERAL (VALUES
  ('EP45-R01_ROWS', $1::text, rows::text),
  ('EP45-R02_MINUTES', $2::text, minutes::text),
  ('EP45-R03_MIN_DATE', $3::text, min_date::text),
  ('EP45-R04_MAX_DATE', $4::text, max_date::text),
  ('EP45-R05_CONTRACT', '0', contract_violations::text)
) v(id, expected, actual);
