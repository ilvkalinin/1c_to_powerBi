-- Read-only candidate control for the line-level return path of the supplied
-- 1C report "Продажи доп пакетов". Parameters: $1 = inclusive start date,
-- $2 = exclusive end date. No target object is referenced or changed.
WITH params AS (
    SELECT $1::date AS date_from, $2::date AS date_to
), package_stock AS MATERIALIZED (
    SELECT d._idrref AS receipt_ref,
           v._lineno4914::integer AS package_line_no,
           v._fld4917 AS package_line_key,
           r._fld681rref AS adult_ref,
           stock._fld4932rref AS product_ref,
           stock._fld4933rref AS party_ref,
           stock._fld4930::numeric AS stock_quantity,
           stock._fld4938::numeric AS stock_amount
    FROM public._document346_vt4913 AS v
    JOIN public._document346 AS d
      ON d._idrref = v._document346_idrref
    JOIN public._reference59 AS r
      ON r._idrref = v._fld4915rref
    JOIN public._document346_vt4924 AS stock
      ON stock._document346_idrref = v._document346_idrref
     AND stock._fld4929 = v._fld4917
    CROSS JOIN params AS p
    WHERE d._date_time >= p.date_from
      AND d._date_time < p.date_to
      AND d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND r._fld672 > r._fld671
      AND r._fld670 IS NOT NULL
      AND r._fld681rref IS NOT NULL
), movement_keys AS MATERIALIZED (
    SELECT DISTINCT receipt_ref, adult_ref, product_ref, party_ref
    FROM package_stock
    WHERE product_ref IS NOT NULL
      AND party_ref IS NOT NULL
), sale_movements AS MATERIALIZED (
    SELECT a._fld7647_rrref AS receipt_ref,
           a._fld7648rref AS adult_ref,
           a._fld7649rref AS product_ref,
           a._fld7650rref AS party_ref,
           sum(a._fld7657)::numeric AS movement_quantity,
           sum(a._fld7659)::numeric AS movement_amount,
           count(*)::bigint AS movement_rows
    FROM public._accumrg7646 AS a
    WHERE (a._fld7647_rrref, a._fld7648rref, a._fld7649rref, a._fld7650rref) IN (
        SELECT receipt_ref, adult_ref, product_ref, party_ref
        FROM movement_keys
    )
    GROUP BY a._fld7647_rrref, a._fld7648rref, a._fld7649rref, a._fld7650rref
), attributed AS (
    SELECT ps.*,
           sm.movement_quantity,
           sm.movement_amount,
           sm.movement_rows,
           count(*) OVER (
               PARTITION BY ps.receipt_ref, ps.adult_ref, ps.product_ref, ps.party_ref
           ) AS package_lines_per_movement_key
    FROM package_stock AS ps
    LEFT JOIN sale_movements AS sm
      USING (receipt_ref, adult_ref, product_ref, party_ref)
)
SELECT count(*)::bigint AS package_lines,
       count(DISTINCT (receipt_ref, package_line_no))::bigint AS package_keys,
       count(*) FILTER (WHERE party_ref IS NULL)::bigint AS null_party_lines,
       count(*) FILTER (WHERE movement_rows IS NULL)::bigint AS no_movement_key,
       count(*) FILTER (WHERE package_lines_per_movement_key > 1)::bigint
           AS multi_package_movement_key_lines,
       count(*) FILTER (WHERE movement_quantity < 0 OR movement_amount < 0)::bigint
           AS negative_line_candidates,
       sum(stock_quantity)::numeric AS stock_quantity_total,
       sum(stock_amount)::numeric AS stock_amount_total,
       sum(movement_quantity)::numeric AS attributed_movement_quantity_total,
       sum(movement_amount)::numeric AS attributed_movement_amount_total
FROM attributed;
