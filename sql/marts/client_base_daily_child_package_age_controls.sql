-- Independent BR-038 source control for mart.client_base_daily.
-- Bind $1 = inclusive BR-003 horizon start, $2 = exclusive horizon end.
-- This query intentionally does not reuse extract interval classification or
-- demographic events. It rederives only package-origin child client-days whose
-- factual age is 14+ or unknown; target values must match exactly.
WITH params AS (
    SELECT $1::date AS horizon_start, $2::date AS horizon_end
), child_raw AS MATERIALIZED (
    SELECT v._document346_idrref AS receipt_ref,
           r._idrref AS contract_ref,
           child._idrref AS client_id,
           r._fld687rref AS club_ref,
           adult._idrref AS adult_ref,
           stock._fld4932rref AS product_ref,
           greatest(r._fld671::date, d._date_time::date) AS candidate_start,
           r._fld672::date AS active_to
    FROM public._document346_vt4913 AS v
    JOIN public._document346 AS d
      ON d._idrref = v._document346_idrref
    JOIN public._reference59 AS r
      ON r._idrref = v._fld4915rref
    JOIN public._reference141x1 AS child
      ON child._idrref = v._fld4916rref
    JOIN public._reference141x1 AS adult
      ON adult._idrref = r._fld681rref
    JOIN public._reference132 AS club
      ON club._idrref = r._fld687rref
    LEFT JOIN public._document346_vt4924 AS stock
      ON stock._document346_idrref = d._idrref
     AND stock._fld4929 = v._fld4917
    CROSS JOIN params AS p
    WHERE d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND r._fld672 > r._fld671
      AND (r._fld670 IS NOT NULL OR r._fld670 <> TIMESTAMP '0001-01-01 00:00:00')
      AND r._fld681rref IS NOT NULL
      AND child._code IS NOT NULL
      AND club._description IS NOT NULL
      AND r._description::varchar NOT ILIKE '%сотруд%'
      AND r._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND r._fld672 >= p.horizon_start - 1
), child_sales AS MATERIALIZED (
    SELECT a._fld7647_rrref AS receipt_ref,
           a._fld7648rref AS adult_ref,
           a._fld7649rref AS product_ref,
           sum(a._fld7657)::numeric AS net_quantity,
           sum(a._fld7659)::numeric AS net_amount
    FROM public._accumrg7646 AS a
    JOIN (
        SELECT DISTINCT receipt_ref, adult_ref, product_ref
        FROM child_raw
        WHERE product_ref IS NOT NULL
    ) AS keyset
      ON keyset.receipt_ref = a._fld7647_rrref
     AND keyset.adult_ref = a._fld7648rref
     AND keyset.product_ref = a._fld7649rref
    GROUP BY a._fld7647_rrref, a._fld7648rref, a._fld7649rref
), child_contract_ranges AS MATERIALIZED (
    SELECT cr.contract_ref,
           cr.client_id,
           cr.club_ref,
           max(cr.candidate_start)::date AS active_from,
           max(cr.active_to)::date AS active_to
    FROM child_raw AS cr
    LEFT JOIN child_sales AS sale
      USING (receipt_ref, adult_ref, product_ref)
    CROSS JOIN params AS p
    WHERE sale.net_quantity IS NULL
       OR (sale.net_quantity > 0 AND sale.net_amount > 0)
    GROUP BY cr.contract_ref, cr.client_id, cr.club_ref, p.horizon_start, p.horizon_end
    HAVING max(cr.active_to)::date >= p.horizon_start - 1
       AND max(cr.candidate_start)::date < p.horizon_end
), child_intervals AS (
    SELECT client_id,
           club_ref,
           daterange(
               greatest(active_from + 1, p.horizon_start),
               least(active_to + 2, p.horizon_end),
               '[)'
           ) AS active_range
    FROM child_contract_ranges
    CROSS JOIN params AS p
    WHERE greatest(active_from + 1, p.horizon_start) < least(active_to + 2, p.horizon_end)
), club_days AS (
    SELECT ranges.client_id,
           day::date AS report_date
    FROM (
        SELECT client_id, club_ref, range_agg(active_range) AS active_ranges
        FROM child_intervals
        GROUP BY client_id, club_ref
    ) AS ranges
    CROSS JOIN LATERAL unnest(ranges.active_ranges) AS part(active_range)
    CROSS JOIN LATERAL generate_series(
        lower(part.active_range), upper(part.active_range) - 1, INTERVAL '1 day'
    ) AS day
), network_days AS (
    SELECT ranges.client_id,
           day::date AS report_date
    FROM (
        SELECT client_id, range_agg(active_range) AS active_ranges
        FROM child_intervals
        GROUP BY client_id
    ) AS ranges
    CROSS JOIN LATERAL unnest(ranges.active_ranges) AS part(active_range)
    CROSS JOIN LATERAL generate_series(
        lower(part.active_range), upper(part.active_range) - 1, INTERVAL '1 day'
    ) AS day
), client_birth AS (
    SELECT cl._idrref AS client_id,
           nullif(cl._fld1507::date, DATE '0001-01-01') AS birth_date
    FROM public._reference141x1 AS cl
    JOIN (
        SELECT client_id FROM club_days
        UNION
        SELECT client_id FROM network_days
    ) AS used
      ON used.client_id = cl._idrref
), scoped_days AS (
    SELECT 'club'::text AS scope_level, client_id, report_date FROM club_days
    UNION ALL
    SELECT 'network'::text, client_id, report_date FROM network_days
)
SELECT scope_level,
       count(*)::bigint AS client_days
FROM scoped_days
JOIN client_birth USING (client_id)
WHERE birth_date IS NULL
   OR extract(year FROM age(report_date, birth_date)) >= 14
GROUP BY scope_level
ORDER BY scope_level;
