-- Independent BR-037/BR-038 retention control at 2026-07-01.
-- It returns only aggregate baseline/retained counts; no client ID leaves VM-1.
WITH comparisons AS (
    SELECT DATE '2026-07-01' AS report_date, 'year_start'::text AS comparison_type, DATE '2026-01-01' AS comparison_date
    UNION ALL
    SELECT DATE '2026-07-01', 'previous_year'::text, DATE '2025-07-01'
), control_dates AS (
    SELECT report_date FROM comparisons
    UNION
    SELECT comparison_date FROM comparisons
), membership_raw AS MATERIALIZED (
    SELECT ab._fld681rref AS client_id, ab._fld687rref AS club_ref,
           ab._fld671::date AS active_from, ab._fld672::date AS active_to
    FROM public._reference59 AS ab
    JOIN public._reference141x1 AS cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 AS club ON club._idrref = ab._fld687rref
    WHERE ab._fld672 >= DATE '2025-06-30'
      AND ab._fld671 < DATE '2026-07-01'
      AND ab._fld672 > ab._fld671
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
), child_raw AS MATERIALIZED (
    SELECT v._document346_idrref AS receipt_ref, r._idrref AS contract_ref,
           child._idrref AS client_id, r._fld687rref AS club_ref,
           adult._idrref AS adult_ref, stock._fld4932rref AS product_ref,
           greatest(r._fld671::date, d._date_time::date) AS candidate_start,
           r._fld672::date AS active_to
    FROM public._document346_vt4913 AS v
    JOIN public._document346 AS d ON d._idrref = v._document346_idrref
    JOIN public._reference59 AS r ON r._idrref = v._fld4915rref
    JOIN public._reference141x1 AS child ON child._idrref = v._fld4916rref
    JOIN public._reference141x1 AS adult ON adult._idrref = r._fld681rref
    JOIN public._reference132 AS club ON club._idrref = r._fld687rref
    LEFT JOIN public._document346_vt4924 AS stock
      ON stock._document346_idrref = d._idrref AND stock._fld4929 = v._fld4917
    WHERE d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND r._fld672 > r._fld671
      AND (r._fld670 IS NOT NULL OR r._fld670 <> TIMESTAMP '0001-01-01 00:00:00')
      AND r._fld681rref IS NOT NULL AND child._code IS NOT NULL
      AND club._description IS NOT NULL
      AND r._description::varchar NOT ILIKE '%сотруд%'
      AND r._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND r._fld672 >= DATE '2025-06-30'
), child_sales AS MATERIALIZED (
    SELECT a._fld7647_rrref AS receipt_ref, a._fld7648rref AS adult_ref,
           a._fld7649rref AS product_ref, sum(a._fld7657)::numeric AS net_quantity,
           sum(a._fld7659)::numeric AS net_amount
    FROM public._accumrg7646 AS a
    JOIN (SELECT DISTINCT receipt_ref, adult_ref, product_ref FROM child_raw WHERE product_ref IS NOT NULL) AS k
      ON k.receipt_ref = a._fld7647_rrref AND k.adult_ref = a._fld7648rref AND k.product_ref = a._fld7649rref
    GROUP BY a._fld7647_rrref, a._fld7648rref, a._fld7649rref
), child_contracts AS MATERIALIZED (
    SELECT cr.contract_ref, cr.client_id, cr.club_ref,
           max(cr.candidate_start)::date AS active_from, max(cr.active_to)::date AS active_to
    FROM child_raw AS cr
    LEFT JOIN child_sales AS sale USING (receipt_ref, adult_ref, product_ref)
    WHERE sale.net_quantity IS NULL OR (sale.net_quantity > 0 AND sale.net_amount > 0)
    GROUP BY cr.contract_ref, cr.client_id, cr.club_ref
), club_candidates AS MATERIALIZED (
    SELECT d.report_date, m.client_id, m.club_ref, false AS is_child
    FROM control_dates AS d JOIN membership_raw AS m
      ON m.active_from < d.report_date AND m.active_to >= d.report_date - 1
    UNION ALL
    SELECT d.report_date, c.client_id, c.club_ref, true AS is_child
    FROM control_dates AS d JOIN child_contracts AS c
      ON c.active_from < d.report_date AND c.active_to >= d.report_date - 1
), club_scope AS MATERIALIZED (
    SELECT DISTINCT ON (report_date, club_ref, client_id) report_date, club_ref, client_id, is_child
    FROM club_candidates
    ORDER BY report_date, club_ref, client_id, is_child DESC
), network_scope AS MATERIALIZED (
    SELECT DISTINCT ON (report_date, client_id) report_date, client_id, is_child
    FROM club_scope
    ORDER BY report_date, client_id, is_child DESC
), baseline_cohort AS (
    SELECT c.report_date, c.comparison_type, c.comparison_date,
           'club'::text AS scope_level, b.club_ref AS baseline_club_ref, b.client_id
    FROM comparisons AS c JOIN club_scope AS b ON b.report_date = c.comparison_date
    UNION ALL
    SELECT c.report_date, c.comparison_type, c.comparison_date,
           'network'::text, NULL::bytea, b.client_id
    FROM comparisons AS c JOIN network_scope AS b ON b.report_date = c.comparison_date
)
SELECT b.comparison_type, b.scope_level,
       count(*)::bigint AS baseline_client_count,
       count(current_set.client_id)::bigint AS retained_client_count,
       count(*) FILTER (WHERE current_set.is_child)::bigint AS retained_child_package_clients
FROM baseline_cohort AS b
LEFT JOIN network_scope AS current_set
  ON current_set.report_date = b.report_date AND current_set.client_id = b.client_id
GROUP BY b.comparison_type, b.scope_level
ORDER BY b.comparison_type, b.scope_level;
