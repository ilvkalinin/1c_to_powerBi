-- Immutable source extract for mart.children_package_sale.
-- Parameters: $1/$2 = movement-period batch; $3/$4 = full receipt horizon.
-- Source is read-only. BR-039 preserves the supplied 1C report's return
-- calculation; current Power BI membership eligibility is applied before the
-- final child-only output.
WITH params AS (
    SELECT $1::date AS movement_date_from,
           $2::date AS movement_date_to,
           $3::date AS receipt_date_from,
           $4::date AS receipt_date_to
), preliminary AS MATERIALIZED (
    SELECT DISTINCT
           a._fld7647_rrref AS receipt_ref,
           receipt._date_time AS sale_at,
           receipt._fld4910rref AS receipt_status_ref,
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
           package._fld4916rref AS child_ref,
           package._fld4915rref AS membership_ref,
           membership._fld687rref AS access_club_ref,
           membership._fld671::date AS membership_start_date,
           membership._fld672::date AS membership_end_date,
           membership._fld674::date AS membership_purchase_date,
           membership._fld670::date AS membership_activation_date,
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
    JOIN public._reference59 AS membership
      ON membership._idrref = package._fld4915rref
    WHERE receipt._posted
      AND NOT receipt._marked
      AND membership._fld672 > membership._fld671
      AND membership._fld670 IS NOT NULL
      AND membership._fld681rref IS NOT NULL
      AND stock._document346_idrref IN (SELECT receipt_ref FROM preliminary)
), report_output AS MATERIALIZED (
    SELECT DISTINCT
           p.sale_at,
           p.receipt_status_ref,
           p.sale_club_ref,
           p.sale_employee_ref,
           p.adult_ref,
           p.product_ref,
           d.child_ref,
           d.membership_ref,
           d.access_club_ref,
           d.membership_start_date,
           d.membership_end_date,
           d.membership_purchase_date,
           d.membership_activation_date,
           p.movement_kind,
           CASE
               WHEN p.movement_kind = 'Расход' THEN
                   -CASE WHEN d.stock_amount_without_discount - p.movement_amount_without_discount < 0 THEN 0::numeric
                         WHEN p.movement_amount_without_discount <> d.stock_amount_without_discount THEN d.stock_amount_without_discount
                         ELSE p.movement_amount_without_discount END
               ELSE CASE WHEN d.stock_amount_without_discount - p.movement_amount_without_discount < 0 THEN 0::numeric
                         WHEN p.movement_amount_without_discount <> d.stock_amount_without_discount THEN d.stock_amount_without_discount
                         ELSE p.movement_amount_without_discount END
            END AS package_amount_without_discount,
           CASE
               WHEN p.movement_kind = 'Расход' THEN
                   -CASE WHEN p.movement_amount <> d.stock_amount THEN d.stock_amount ELSE p.movement_amount END
               ELSE CASE WHEN p.movement_amount <> d.stock_amount THEN d.stock_amount ELSE p.movement_amount END
            END AS package_amount,
           CASE
               WHEN p.movement_kind = 'Расход' THEN
                   -CASE WHEN p.movement_quantity <> d.stock_quantity THEN d.stock_quantity ELSE p.movement_quantity END
               ELSE CASE WHEN p.movement_quantity <> d.stock_quantity THEN d.stock_quantity ELSE p.movement_quantity END
            END AS package_count
    FROM preliminary AS p
    LEFT JOIN document_package_lines AS d
      ON d.receipt_ref = p.receipt_ref
     AND d.adult_ref = p.adult_ref
), keyed_output AS MATERIALIZED (
    SELECT r.*,
           md5(concat_ws('|',
               'sale_at=' || r.sale_at::text,
               'sale_club=' || coalesce(encode(r.sale_club_ref, 'hex'), '<null>'),
               'sale_employee=' || coalesce(encode(r.sale_employee_ref, 'hex'), '<null>'),
               'product=' || coalesce(encode(r.product_ref, 'hex'), '<null>'),
               'adult=' || coalesce(encode(r.adult_ref, 'hex'), '<null>'),
               'child=' || coalesce(encode(r.child_ref, 'hex'), '<null>'),
               'membership=' || coalesce(encode(r.membership_ref, 'hex'), '<null>'),
               'access_club=' || coalesce(encode(r.access_club_ref, 'hex'), '<null>'),
               'membership_start=' || coalesce(r.membership_start_date::text, '<null>'),
               'membership_end=' || coalesce(r.membership_end_date::text, '<null>'),
               'movement_kind=' || r.movement_kind,
               'amount_without_discount=' || coalesce(r.package_amount_without_discount::text, '<null>'),
               'amount=' || coalesce(r.package_amount::text, '<null>'),
               'quantity=' || coalesce(r.package_count::text, '<null>')
           )) AS report_row_id
    FROM report_output AS r
    WHERE r.child_ref IS NOT NULL
)
SELECT k.report_row_id,
       k.sale_at,
       k.sale_at::date AS sale_date,
       encode(k.receipt_status_ref, 'hex') AS receipt_status_id,
       encode(k.sale_club_ref, 'hex') AS source_sale_club_id,
       encode(k.sale_employee_ref, 'hex') AS source_sale_employee_id,
       encode(k.access_club_ref, 'hex') AS club_id,
       access_club._description::text AS club_name,
       encode(k.membership_ref, 'hex') AS membership_id,
       membership._code::text AS membership_code,
       membership._description::text AS membership_name,
       k.membership_purchase_date,
       k.membership_activation_date,
       k.membership_start_date,
       k.membership_end_date,
       encode(k.adult_ref, 'hex') AS adult_client_id,
       adult._code::text AS adult_client_code,
       adult._description::text AS adult_client_name,
       encode(k.child_ref, 'hex') AS child_client_id,
       child._code::text AS child_client_code,
       child._description::text AS child_client_name,
       encode(k.product_ref, 'hex') AS product_id,
       product._description::text AS product_name,
       k.package_amount::numeric(15, 2) AS package_amount,
       k.package_amount_without_discount::numeric(15, 2) AS package_amount_without_discount,
       k.package_count::numeric(15, 3) AS package_count,
       (date_trunc('month', k.sale_at)::date = date_trunc('month', k.membership_purchase_date)::date)
           AS sold_correctly_flag,
       k.movement_kind
FROM keyed_output AS k
JOIN public._reference59 AS membership ON membership._idrref = k.membership_ref
JOIN public._reference141x1 AS adult ON adult._idrref = k.adult_ref
JOIN public._reference141x1 AS child ON child._idrref = k.child_ref
JOIN public._reference163 AS product ON product._idrref = k.product_ref
LEFT JOIN public._reference132 AS access_club ON access_club._idrref = k.access_club_ref;
