SELECT count(*)::bigint AS child_output_rows,
       count(DISTINCT report_row_id)::bigint AS distinct_report_row_ids,
       count(*) FILTER (WHERE movement_kind = 'Расход')::bigint AS return_child_output_rows,
       sum(package_count)::numeric AS child_quantity_total,
       sum(package_amount)::numeric AS child_amount_total,
       sum(package_amount) FILTER (WHERE movement_kind = 'Расход')::numeric
           AS child_return_amount_total,
       count(*) FILTER (WHERE sale_date >= $2::date)::bigint AS future_sale_rows,
       count(*) FILTER (WHERE club_name IS NULL)::bigint AS nullable_access_club_names
FROM mart.children_package_sale
WHERE sale_date >= $1::date
  AND sale_date < $2::date;
