-- Independent source control for mart.client_base_daily.
-- Bind $1 = inclusive BR-003 horizon start, $2 = exclusive horizon end.
-- It uses merged active-client intervals and daily deltas, not the extract's
-- client-day demographic expansion. Expected: one positive total per day and
-- scope; its totals must equal the sum of the staged aggregate rows exactly.
WITH params AS (
    SELECT $1::date AS horizon_start, $2::date AS horizon_end
), calendar AS MATERIALIZED (
    SELECT day::date AS report_date
    FROM params,
         generate_series(horizon_start, horizon_end - 1, INTERVAL '1 day') AS day
), membership_raw AS MATERIALIZED (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_ref,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 AS ab
    JOIN public._reference141x1 AS cl
      ON cl._idrref = ab._fld681rref
    JOIN public._reference132 AS club
      ON club._idrref = ab._fld687rref
    CROSS JOIN params AS p
    WHERE ab._fld672 >= p.horizon_start - 1
      AND ab._fld671 < p.horizon_end
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
), child_valid_sales AS MATERIALIZED (
    SELECT cr.*
    FROM child_raw AS cr
    LEFT JOIN child_sales AS sale
      USING (receipt_ref, adult_ref, product_ref)
    WHERE sale.net_quantity IS NULL
       OR (sale.net_quantity > 0 AND sale.net_amount > 0)
), child_contract_ranges AS MATERIALIZED (
    SELECT contract_ref,
           client_id,
           club_ref,
           max(candidate_start)::date AS active_from,
           max(active_to)::date AS active_to
    FROM child_valid_sales
    CROSS JOIN params AS p
    GROUP BY contract_ref, client_id, club_ref, p.horizon_start, p.horizon_end
    HAVING max(active_to)::date >= p.horizon_start - 1
       AND max(candidate_start)::date < p.horizon_end
), current_membership AS MATERIALIZED (
    SELECT client_id, club_ref, active_from, active_to
    FROM membership_raw
    UNION ALL
    SELECT client_id, club_ref, active_from, active_to
    FROM child_contract_ranges
), club_ranges AS (
    SELECT client_id,
           club_ref,
           greatest(active_from + 1, p.horizon_start) AS lower_day,
           least(active_to + 1, p.horizon_end - 1) AS upper_day
    FROM current_membership
    CROSS JOIN params AS p
), club_ordered AS (
    SELECT *, max(upper_day) OVER (
        PARTITION BY client_id, club_ref
        ORDER BY lower_day, upper_day
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS previous_upper_day
    FROM club_ranges
), club_numbered AS (
    SELECT *, sum(CASE WHEN previous_upper_day IS NULL
                             OR lower_day > previous_upper_day + 1
                        THEN 1 ELSE 0 END) OVER (
        PARTITION BY client_id, club_ref
        ORDER BY lower_day, upper_day
    ) AS island_id
    FROM club_ordered
), club_islands AS MATERIALIZED (
    SELECT client_id, club_ref, island_id,
           min(lower_day) AS lower_day,
           max(upper_day) AS upper_day
    FROM club_numbered
    GROUP BY client_id, club_ref, island_id
), client_ranges AS (
    SELECT client_id,
           greatest(active_from + 1, p.horizon_start) AS lower_day,
           least(active_to + 1, p.horizon_end - 1) AS upper_day
    FROM current_membership
    CROSS JOIN params AS p
), client_ordered AS (
    SELECT *, max(upper_day) OVER (
        PARTITION BY client_id
        ORDER BY lower_day, upper_day
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS previous_upper_day
    FROM client_ranges
), client_numbered AS (
    SELECT *, sum(CASE WHEN previous_upper_day IS NULL
                             OR lower_day > previous_upper_day + 1
                        THEN 1 ELSE 0 END) OVER (
        PARTITION BY client_id
        ORDER BY lower_day, upper_day
    ) AS island_id
    FROM client_ordered
), client_islands AS MATERIALIZED (
    SELECT client_id, island_id,
           min(lower_day) AS lower_day,
           max(upper_day) AS upper_day
    FROM client_numbered
    GROUP BY client_id, island_id
), club_events AS (
    SELECT club_ref, lower_day AS report_date, 1::bigint AS delta
    FROM club_islands
    UNION ALL
    SELECT club_ref, upper_day + 1, -1::bigint
    FROM club_islands
), club_daily AS (
    SELECT report_date,
           club_ref,
           sum(delta) OVER (PARTITION BY club_ref ORDER BY report_date) AS client_count
    FROM (
        SELECT c.report_date,
               club.club_ref,
               coalesce(sum(e.delta), 0)::bigint AS delta
        FROM calendar AS c
        CROSS JOIN (SELECT DISTINCT club_ref FROM club_islands) AS club
        LEFT JOIN club_events AS e
          ON e.report_date = c.report_date
         AND e.club_ref = club.club_ref
        GROUP BY c.report_date, club.club_ref
    ) AS event_days
), network_events AS (
    SELECT lower_day AS report_date, 1::bigint AS delta
    FROM client_islands
    UNION ALL
    SELECT upper_day + 1, -1::bigint
    FROM client_islands
), network_events_by_day AS (
    SELECT c.report_date,
           coalesce(sum(e.delta), 0)::bigint AS delta
    FROM calendar AS c
    LEFT JOIN network_events AS e
      ON e.report_date = c.report_date
    GROUP BY c.report_date
), network_daily AS (
    SELECT report_date,
           sum(delta) OVER (ORDER BY report_date) AS client_count
    FROM network_events_by_day
), network_total AS (
    SELECT report_date, max(client_count)::bigint AS client_count
    FROM network_daily
    GROUP BY report_date
), club_total AS (
    SELECT report_date, sum(client_count)::bigint AS client_count
    FROM club_daily
    GROUP BY report_date
)
SELECT report_date, 'club'::text AS scope_level, client_count
FROM club_total
UNION ALL
SELECT report_date, 'network'::text, client_count
FROM network_total
ORDER BY report_date, scope_level;
