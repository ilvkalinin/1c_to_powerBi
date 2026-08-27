-- Read-only translation of the supplied 1C report "Продажи доп пакетов",
-- restricted to the observed child-package type "Дополнительный клиент".
-- Parameters: $1/$2 = movement-period batch; $3/$4 = full receipt horizon.
-- The final LEFT JOIN deliberately matches the ERF: sale document + adult
-- client, not package line, product or party. It is a control, not a load.
WITH params AS (
    SELECT $1::date AS movement_date_from,
           $2::date AS movement_date_to,
           $3::date AS receipt_date_from,
           $4::date AS receipt_date_to
), preliminary AS MATERIALIZED (
    SELECT DISTINCT
           a._fld7647_rrref AS receipt_ref,
           receipt._date_time AS sale_at,
           receipt._fld4895rref AS sale_club_ref,
           receipt._fld4909rref AS sale_employee_ref,
           a._fld7648rref AS adult_ref,
           a._fld7649rref AS product_ref,
           a._fld7657::numeric AS movement_quantity,
           a._fld7659::numeric AS movement_amount,
           a._fld7660::numeric AS movement_amount_without_discount,
           CASE WHEN a._fld7660 < 0 THEN 'Расход' ELSE 'Приход' END AS movement_kind
    FROM public._accumrg7646 AS a
    JOIN public._document346 AS receipt
      ON receipt._idrref = a._fld7647_rrref
    JOIN public._reference163 AS product
      ON product._idrref = a._fld7649rref
    CROSS JOIN params AS p
    WHERE a._period >= p.movement_date_from
      AND a._period < p.movement_date_to
      AND receipt._date_time >= p.receipt_date_from
      AND receipt._date_time < p.receipt_date_to
      AND receipt._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND product._fld1795rref = decode('b5fa1353811819464b0f3d2abc5a70de', 'hex')
), document_package_lines AS MATERIALIZED (
    SELECT DISTINCT
           stock._document346_idrref AS receipt_ref,
           receipt._fld4894rref AS adult_ref,
           package._lineno4914::integer AS package_line_no,
           package._fld4917 AS package_line_key,
           package._fld4916rref AS child_ref,
           package._fld4915rref AS membership_ref,
           membership._fld681rref AS membership_adult_ref,
           membership._fld687rref AS access_club_ref,
           membership._fld671::date AS membership_start_date,
           membership._fld672::date AS membership_end_date,
           membership._fld670::date AS membership_activation_date,
           membership._fld674::date AS membership_purchase_date,
           stock._fld4932rref AS stock_product_ref,
           stock._fld4930::numeric AS stock_quantity,
           stock._fld4938::numeric AS stock_amount,
           (stock._fld4938 + stock._fld4939 + stock._fld4942)::numeric
               AS stock_amount_without_discount
    FROM public._document346_vt4924 AS stock
    JOIN public._document346_vt4913 AS package
      ON package._document346_idrref = stock._document346_idrref
     AND package._fld4917 = stock._fld4929
    JOIN public._document346 AS receipt
      ON receipt._idrref = stock._document346_idrref
    LEFT JOIN public._reference59 AS membership
      ON membership._idrref = package._fld4915rref
    WHERE receipt._posted
      AND NOT receipt._marked
      -- Current Power BI keeps only an eligible adult membership. The legacy
      -- `IS NOT NULL OR <> sentinel` predicate is equivalent to NOT NULL.
      AND membership._fld672 > membership._fld671
      AND membership._fld670 IS NOT NULL
      AND membership._fld681rref IS NOT NULL
      AND stock._document346_idrref IN (SELECT receipt_ref FROM preliminary)
), erf_output AS MATERIALIZED (
    SELECT DISTINCT
           p.sale_at,
           p.sale_club_ref,
           p.sale_employee_ref,
           p.product_ref,
           p.adult_ref,
           d.child_ref,
           d.membership_ref,
           d.membership_adult_ref,
           d.access_club_ref,
           d.membership_start_date,
           d.membership_end_date,
           d.membership_activation_date,
           d.membership_purchase_date,
           d.stock_product_ref,
           p.movement_kind,
           CASE
               WHEN p.movement_kind = 'Расход' THEN
                   -CASE
                       WHEN d.stock_amount_without_discount - p.movement_amount_without_discount < 0 THEN 0::numeric
                       WHEN p.movement_amount_without_discount <> d.stock_amount_without_discount THEN d.stock_amount_without_discount
                       ELSE p.movement_amount_without_discount
                    END
               ELSE CASE
                       WHEN d.stock_amount_without_discount - p.movement_amount_without_discount < 0 THEN 0::numeric
                       WHEN p.movement_amount_without_discount <> d.stock_amount_without_discount THEN d.stock_amount_without_discount
                       ELSE p.movement_amount_without_discount
                    END
            END AS amount_without_discount,
           CASE
               WHEN p.movement_kind = 'Расход' THEN
                   -CASE WHEN p.movement_amount <> d.stock_amount THEN d.stock_amount ELSE p.movement_amount END
               ELSE CASE WHEN p.movement_amount <> d.stock_amount THEN d.stock_amount ELSE p.movement_amount END
            END AS package_amount,
           CASE
               WHEN p.movement_kind = 'Расход' THEN
                   -CASE WHEN p.movement_quantity <> d.stock_quantity THEN d.stock_quantity ELSE p.movement_quantity END
               ELSE CASE WHEN p.movement_quantity <> d.stock_quantity THEN d.stock_quantity ELSE p.movement_quantity END
            END AS package_quantity,
           md5(concat_ws('|',
               'sale_at=' || p.sale_at::text,
               'sale_club=' || coalesce(encode(p.sale_club_ref, 'hex'), '<null>'),
               'sale_employee=' || coalesce(encode(p.sale_employee_ref, 'hex'), '<null>'),
               'product=' || coalesce(encode(p.product_ref, 'hex'), '<null>'),
               'adult=' || coalesce(encode(p.adult_ref, 'hex'), '<null>'),
               'child=' || coalesce(encode(d.child_ref, 'hex'), '<null>'),
               'membership=' || coalesce(encode(d.membership_ref, 'hex'), '<null>'),
               'access_club=' || coalesce(encode(d.access_club_ref, 'hex'), '<null>'),
               'membership_start=' || coalesce(d.membership_start_date::text, '<null>'),
               'membership_end=' || coalesce(d.membership_end_date::text, '<null>'),
               'movement_kind=' || p.movement_kind,
               'amount_without_discount=' || coalesce((CASE
                   WHEN p.movement_kind = 'Расход' THEN -CASE
                       WHEN d.stock_amount_without_discount - p.movement_amount_without_discount < 0 THEN 0::numeric
                       WHEN p.movement_amount_without_discount <> d.stock_amount_without_discount THEN d.stock_amount_without_discount
                       ELSE p.movement_amount_without_discount END
                   ELSE CASE
                       WHEN d.stock_amount_without_discount - p.movement_amount_without_discount < 0 THEN 0::numeric
                       WHEN p.movement_amount_without_discount <> d.stock_amount_without_discount THEN d.stock_amount_without_discount
                       ELSE p.movement_amount_without_discount END
                   END)::text, '<null>'),
               'amount=' || coalesce((CASE
                   WHEN p.movement_kind = 'Расход' THEN -CASE WHEN p.movement_amount <> d.stock_amount THEN d.stock_amount ELSE p.movement_amount END
                   ELSE CASE WHEN p.movement_amount <> d.stock_amount THEN d.stock_amount ELSE p.movement_amount END
                   END)::text, '<null>'),
               'quantity=' || coalesce((CASE
                   WHEN p.movement_kind = 'Расход' THEN -CASE WHEN p.movement_quantity <> d.stock_quantity THEN d.stock_quantity ELSE p.movement_quantity END
                   ELSE CASE WHEN p.movement_quantity <> d.stock_quantity THEN d.stock_quantity ELSE p.movement_quantity END
                   END)::text, '<null>')
           )) AS report_row_id
    FROM preliminary AS p
    LEFT JOIN document_package_lines AS d
      ON d.receipt_ref = p.receipt_ref
     AND d.adult_ref = p.adult_ref
), erf_enriched AS MATERIALIZED (
    SELECT e.*,
           child._idrref AS matched_child_ref,
           adult._idrref AS matched_adult_ref,
           access_club._idrref AS matched_access_club_ref
    FROM erf_output AS e
    LEFT JOIN public._reference141x1 AS child
      ON child._idrref = e.child_ref
    LEFT JOIN public._reference141x1 AS adult
      ON adult._idrref = e.adult_ref
    LEFT JOIN public._reference132 AS access_club
      ON access_club._idrref = e.access_club_ref
)
SELECT count(*)::bigint AS erf_output_rows,
       count(*) FILTER (WHERE child_ref IS NULL)::bigint AS erf_rows_without_child,
       count(*) FILTER (WHERE child_ref IS NOT NULL)::bigint AS child_output_rows,
       count(*) FILTER (WHERE movement_kind = 'Расход')::bigint AS return_output_rows,
       count(*) FILTER (WHERE movement_kind = 'Расход' AND child_ref IS NOT NULL)::bigint
           AS return_child_output_rows,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND membership_ref IS NULL)::bigint
           AS child_rows_without_membership,
       count(*) FILTER (
           WHERE child_ref IS NOT NULL
             AND NOT (membership_end_date > membership_start_date
                      AND membership_activation_date IS NOT NULL
                      AND membership_adult_ref IS NOT NULL)
       )::bigint AS excluded_by_current_pbi_membership_filters,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND membership_purchase_date IS NULL)::bigint
           AS null_membership_purchase_dates,
       count(*) FILTER (
           WHERE child_ref IS NOT NULL
             AND membership_purchase_date = DATE '0001-01-01'
       )::bigint AS sentinel_membership_purchase_dates,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND membership_adult_ref IS DISTINCT FROM adult_ref)::bigint
           AS adult_mismatch_to_membership,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND stock_product_ref IS DISTINCT FROM product_ref)::bigint
           AS movement_product_mismatch_to_stock,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND sale_club_ref IS DISTINCT FROM access_club_ref)::bigint
           AS sales_club_mismatch_to_membership_access,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND matched_child_ref IS NULL)::bigint
           AS child_reference_orphans,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND matched_adult_ref IS NULL)::bigint
           AS adult_reference_orphans,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND matched_access_club_ref IS NULL)::bigint
           AS access_club_orphans,
       count(*) FILTER (WHERE child_ref IS NOT NULL AND matched_access_club_ref IS NULL)::bigint
           AS nullable_access_club_names,
       count(*) FILTER (WHERE child_ref IS NOT NULL)
           - count(DISTINCT report_row_id) FILTER (WHERE child_ref IS NOT NULL)
           AS duplicate_report_row_ids,
       coalesce(sum(package_quantity) FILTER (WHERE child_ref IS NOT NULL), 0)::numeric
           AS child_quantity_total,
       coalesce(sum(package_amount) FILTER (WHERE child_ref IS NOT NULL), 0)::numeric
           AS child_amount_total,
       coalesce(sum(package_amount) FILTER (
           WHERE child_ref IS NOT NULL AND movement_kind = 'Расход'
       ), 0)::numeric AS child_return_amount_total
       ,min(sale_at::date) FILTER (WHERE child_ref IS NOT NULL) AS min_sale_date
       ,max(sale_at::date) FILTER (WHERE child_ref IS NOT NULL) AS max_sale_date
FROM erf_enriched;
