-- Positional parameters are source expected controls and BR-003 horizon.
WITH actual AS (
  SELECT count(*)::bigint AS rows_total,
         count(*) FILTER (WHERE source_kind = 'promo_gift')::bigint AS gift_rows,
         count(*) FILTER (WHERE source_kind = 'discount')::bigint AS discount_rows,
         min(application_date) AS min_date, max(application_date) AS max_date,
         coalesce(sum(discount_amount), 0)::numeric AS discount_amount_sum,
         coalesce(sum(price_before_discount), 0)::numeric AS price_before_discount_sum,
         count(*) FILTER (WHERE report_row_id IS NULL OR client_key IS NULL OR client_key = ''
           OR application_date IS NULL OR promo_name IS NULL OR serial_name IS NULL
           OR discount_method IS NULL OR client_stage IS NULL
           OR source_kind NOT IN ('promo_gift','discount'))::bigint AS contract_violations,
         count(*) FILTER (WHERE application_date < $8::date OR application_date >= $9::date)::bigint AS horizon_violations,
         count(*) - count(DISTINCT report_row_id)::bigint AS duplicate_row_ids
  FROM mart.promo_application
)
SELECT control_id, expected, actual, tolerance,
       CASE WHEN expected IS NOT DISTINCT FROM actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM actual CROSS JOIN LATERAL (VALUES
 ('PA-R01_ROWS', $1::text, rows_total::text, '0'),
 ('PA-R02_GIFT_ROWS', $2::text, gift_rows::text, '0'),
 ('PA-R03_DISCOUNT_ROWS', $3::text, discount_rows::text, '0'),
 ('PA-R04_MIN_DATE', $4::text, min_date::text, '0'),
 ('PA-R05_MAX_DATE', $5::text, max_date::text, '0'),
 ('PA-R06_DISCOUNT_SUM', $6::text, discount_amount_sum::text, '0'),
 ('PA-R07_PRICE_SUM', $7::text, price_before_discount_sum::text, '0'),
 ('PA-R08_HORIZON', '0', horizon_violations::text, '0'),
 ('PA-R09_CONTRACT', '0', contract_violations::text, '0'),
 ('PA-R10_ROW_ID', '0', duplicate_row_ids::text, '0')
) AS controls(control_id, expected, actual, tolerance);
