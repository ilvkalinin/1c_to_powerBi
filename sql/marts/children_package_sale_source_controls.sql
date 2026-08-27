-- Read-only Stage 3 admission controls for mart.children_package_sale.
-- Bind $1 = inclusive BR-003 horizon start; $2 = exclusive horizon end.
-- The controls deliberately do not allocate an AccumRg7646 return to a
-- VT4913 child line: a sale group can contain several such lines.
WITH params AS (
    SELECT $1::date AS horizon_start, $2::date AS horizon_end
), child_raw AS MATERIALIZED (
    SELECT d._idrref AS receipt_ref,
           v._lineno4914 AS package_line_no,
           r._fld681rref AS adult_ref,
           v._fld4916rref AS child_ref,
           v._fld4917 AS stock_line_key,
           stock._fld4932rref AS product_ref,
           stock._fld4930::numeric AS stock_quantity,
           stock._fld4938::numeric AS stock_amount
    FROM public._document346 AS d
    JOIN public._document346_vt4913 AS v
      ON v._document346_idrref = d._idrref
    JOIN public._reference59 AS r
      ON r._idrref = v._fld4915rref
    LEFT JOIN public._document346_vt4924 AS stock
      ON stock._document346_idrref = d._idrref
     AND stock._fld4929 = v._fld4917
    CROSS JOIN params AS p
    WHERE d._date_time >= p.horizon_start
      AND d._date_time < p.horizon_end
      AND d._posted
      AND NOT d._marked
      AND d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND r._fld672 > r._fld671
      AND r._fld670 IS NOT NULL
      AND r._fld681rref IS NOT NULL
      AND v._fld4916rref IS NOT NULL
), sale_keys AS MATERIALIZED (
    SELECT DISTINCT receipt_ref, adult_ref, product_ref
    FROM child_raw
    WHERE product_ref IS NOT NULL
), child_sales AS MATERIALIZED (
    SELECT a._fld7647_rrref AS receipt_ref,
           a._fld7648rref AS adult_ref,
           a._fld7649rref AS product_ref,
           sum(a._fld7657)::numeric AS net_quantity,
           sum(a._fld7659)::numeric AS net_amount
    FROM public._accumrg7646 AS a
    WHERE (a._fld7647_rrref, a._fld7648rref, a._fld7649rref) IN (
        SELECT receipt_ref, adult_ref, product_ref
        FROM sale_keys
    )
    GROUP BY a._fld7647_rrref, a._fld7648rref, a._fld7649rref
), lines_with_sales AS MATERIALIZED (
    SELECT c.*,
           s.net_quantity,
           s.net_amount,
           count(*) OVER (
               PARTITION BY c.receipt_ref, c.adult_ref, c.product_ref
           )::bigint AS child_lines_in_sales_group
    FROM child_raw AS c
    LEFT JOIN child_sales AS s
      USING (receipt_ref, adult_ref, product_ref)
)
SELECT 'CPS_SOURCE_ADMISSION'::text AS control_name,
       count(*)::bigint AS package_lines,
       count(DISTINCT (receipt_ref, package_line_no))::bigint AS logical_keys,
       count(*) FILTER (WHERE product_ref IS NULL)::bigint AS missing_stock_product,
       count(*) FILTER (WHERE stock_quantity < 0 OR stock_amount < 0)::bigint
           AS negative_stock_lines,
       count(*) FILTER (WHERE net_quantity IS NULL AND product_ref IS NOT NULL)::bigint
           AS no_sales_group_lines,
       count(*) FILTER (WHERE net_quantity <= 0 OR net_amount <= 0)::bigint
           AS nonpositive_sales_group_lines,
       count(*) FILTER (
           WHERE net_quantity IS NOT NULL AND child_lines_in_sales_group > 1
       )::bigint AS multi_child_line_sales_group_lines
FROM lines_with_sales;
