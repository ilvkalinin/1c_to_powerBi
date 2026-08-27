-- Target reconciliation for mart.children_package_sale.
-- Parameters $1..$9 are independently obtained from
-- children_package_sale_erf_source_control.sql in the same source snapshot:
-- child rows, distinct keys, return rows, quantity, amount, return amount,
-- min date, max date, nullable access-club names. $10/$11 are the horizon.
WITH actual AS (
    SELECT count(*)::bigint AS child_output_rows,
           count(DISTINCT report_row_id)::bigint AS distinct_report_row_ids,
           count(*) FILTER (WHERE movement_kind = 'Расход')::bigint AS return_child_output_rows,
           coalesce(sum(package_count), 0)::numeric AS child_quantity_total,
           coalesce(sum(package_amount), 0)::numeric AS child_amount_total,
           coalesce(sum(package_amount) FILTER (WHERE movement_kind = 'Расход'), 0)::numeric
               AS child_return_amount_total,
           min(sale_date) AS min_sale_date,
           max(sale_date) AS max_sale_date,
           count(*) FILTER (WHERE club_name IS NULL)::bigint AS nullable_access_club_names,
           count(*) FILTER (WHERE sale_date >= $11::date)::bigint AS future_sale_rows,
           count(*) FILTER (
               WHERE sale_date < $10::date OR sale_date >= $11::date
                  OR sale_at IS NULL OR receipt_status_id IS NULL OR club_id IS NULL
                  OR membership_id IS NULL OR membership_code IS NULL OR membership_name IS NULL
                  OR membership_purchase_date IS NULL OR membership_activation_date IS NULL
                  OR membership_start_date IS NULL OR membership_end_date IS NULL
                  OR adult_client_id IS NULL OR adult_client_code IS NULL OR adult_client_name IS NULL
                  OR child_client_id IS NULL OR child_client_code IS NULL OR child_client_name IS NULL
                  OR product_id IS NULL OR product_name IS NULL OR package_amount IS NULL
                  OR package_amount_without_discount IS NULL OR package_count IS NULL
                  OR sold_correctly_flag IS NULL OR movement_kind NOT IN ('Приход', 'Расход')
           )::bigint AS contract_violations
    FROM mart.children_package_sale
    WHERE sale_date >= $10::date
      AND sale_date < $11::date
), checks AS (
    SELECT 'CPS_ROW_COUNT'::text AS control_id, child_output_rows::numeric AS actual,
           $1::numeric AS expected, 0::numeric AS tolerance FROM actual
    UNION ALL SELECT 'CPS_DISTINCT_KEY', distinct_report_row_ids, $2::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_RETURN_ROWS', return_child_output_rows, $3::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_QUANTITY', child_quantity_total, $4::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_AMOUNT', child_amount_total, $5::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_RETURN_AMOUNT', child_return_amount_total, $6::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_MIN_DATE', extract(epoch FROM min_sale_date)::numeric,
                     extract(epoch FROM $7::date)::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_MAX_DATE', extract(epoch FROM max_sale_date)::numeric,
                     extract(epoch FROM $8::date)::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_NULLABLE_ACCESS_CLUB_NAMES', nullable_access_club_names, $9::numeric, 0 FROM actual
    UNION ALL SELECT 'CPS_FUTURE_DATES', future_sale_rows, 0, 0 FROM actual
    UNION ALL SELECT 'CPS_CONTRACT_VIOLATIONS', contract_violations, 0, 0 FROM actual
)
SELECT control_id, actual, expected, tolerance,
       CASE WHEN abs(actual - expected) <= tolerance THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY control_id;
