-- Source-side aggregate for mart.client_base_daily.
-- Bind $1 = inclusive BR-003 horizon start, $2 = exclusive horizon end.
-- Membership islands are split only where age can change. This avoids expanding
-- every active client into every day, while retaining exact BR-005 semantics.
-- No client identifier leaves this query: it is aggregated before COPY.
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
), membership_intervals AS (
    SELECT client_id,
           club_ref,
           daterange(
               greatest(active_from + 1, p.horizon_start),
               least(active_to + 2, p.horizon_end),
               '[)'
           ) AS active_range
    FROM membership_raw
    CROSS JOIN params AS p
    WHERE greatest(active_from + 1, p.horizon_start) < least(active_to + 2, p.horizon_end)
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
), membership_club_multiranges AS MATERIALIZED (
    SELECT client_id, club_ref, range_agg(active_range) AS active_ranges
    FROM membership_intervals
    GROUP BY client_id, club_ref
), child_club_multiranges AS MATERIALIZED (
    SELECT client_id, club_ref, range_agg(active_range) AS active_ranges
    FROM child_intervals
    GROUP BY client_id, club_ref
), club_membership_segments AS (
    SELECT membership.client_id,
           membership.club_ref,
           false AS is_child,
           part.active_range
    FROM membership_club_multiranges AS membership
    LEFT JOIN child_club_multiranges AS child
      USING (client_id, club_ref)
    CROSS JOIN LATERAL unnest(
        membership.active_ranges - coalesce(child.active_ranges, '{}'::datemultirange)
    ) AS part(active_range)
), club_child_segments AS (
    SELECT child.client_id,
           child.club_ref,
           true AS is_child,
           part.active_range
    FROM child_club_multiranges AS child
    CROSS JOIN LATERAL unnest(child.active_ranges) AS part(active_range)
), club_islands AS MATERIALIZED (
    SELECT client_id,
           club_ref,
           is_child,
           lower(active_range)::date AS lower_day,
           (upper(active_range) - 1)::date AS upper_day
    FROM club_membership_segments
    UNION ALL
    SELECT client_id,
           club_ref,
           is_child,
           lower(active_range)::date AS lower_day,
           (upper(active_range) - 1)::date AS upper_day
    FROM club_child_segments
), membership_network_multiranges AS MATERIALIZED (
    SELECT client_id, range_agg(active_range) AS active_ranges
    FROM membership_intervals
    GROUP BY client_id
), child_network_multiranges AS MATERIALIZED (
    SELECT client_id, range_agg(active_range) AS active_ranges
    FROM child_intervals
    GROUP BY client_id
), network_membership_segments AS (
    SELECT membership.client_id,
           false AS is_child,
           part.active_range
    FROM membership_network_multiranges AS membership
    LEFT JOIN child_network_multiranges AS child USING (client_id)
    CROSS JOIN LATERAL unnest(
        membership.active_ranges - coalesce(child.active_ranges, '{}'::datemultirange)
    ) AS part(active_range)
), network_child_segments AS (
    SELECT child.client_id,
           true AS is_child,
           part.active_range
    FROM child_network_multiranges AS child
    CROSS JOIN LATERAL unnest(child.active_ranges) AS part(active_range)
), client_islands AS MATERIALIZED (
    SELECT client_id,
           is_child,
           lower(active_range)::date AS lower_day,
           (upper(active_range) - 1)::date AS upper_day
    FROM network_membership_segments
    UNION ALL
    SELECT client_id,
           is_child,
           lower(active_range)::date AS lower_day,
           (upper(active_range) - 1)::date AS upper_day
    FROM network_child_segments
), client_attributes AS MATERIALIZED (
    SELECT cl._idrref AS client_id,
           cl._fld1507::date AS birth_date,
           CASE encode(cl._fld1527rref, 'hex')
               WHEN 'b64a5b1e2f68583046c1077a96a54ebd' THEN 'Женский'
               WHEN 'b26004420b2465b8457ffa23c30a12aa' THEN 'Мужской'
               ELSE 'Не указано'
           END AS gender
    FROM public._reference141x1 AS cl
    JOIN (SELECT client_id FROM club_islands UNION SELECT client_id FROM client_islands) AS used
      ON used.client_id = cl._idrref
), club_unknown_age_segments AS (
    SELECT ci.club_ref, ci.is_child, ci.lower_day, ci.upper_day,
           NULL::smallint AS age_years, ca.gender
    FROM club_islands AS ci
    JOIN client_attributes AS ca USING (client_id)
    WHERE ca.birth_date IS NULL OR ca.birth_date = DATE '0001-01-01'
), club_known_age_segments AS (
    SELECT ci.club_ref,
           ci.is_child,
           greatest(ci.lower_day, anniversary.anniversary_day) AS lower_day,
           least(ci.upper_day, anniversary.next_anniversary_day - 1) AS upper_day,
           extract(year FROM age(
               greatest(ci.lower_day, anniversary.anniversary_day), ca.birth_date
           ))::smallint AS age_years,
           ca.gender
    FROM club_islands AS ci
    JOIN client_attributes AS ca USING (client_id)
    CROSS JOIN LATERAL generate_series(
        date_trunc('year', ci.lower_day)::date - INTERVAL '1 year',
        date_trunc('year', ci.upper_day)::date,
        INTERVAL '1 year'
    ) AS year_start
    CROSS JOIN LATERAL (
        SELECT (
                   ca.birth_date
                   + make_interval(
                       years => extract(year FROM year_start)::int
                              - extract(year FROM ca.birth_date)::int
                   )
               )::date AS anniversary_day,
               (
                   ca.birth_date
                   + make_interval(
                       years => extract(year FROM year_start)::int + 1
                              - extract(year FROM ca.birth_date)::int
                   )
               )::date AS next_anniversary_day
    ) AS anniversary
    WHERE ca.birth_date IS NOT NULL
      AND ca.birth_date <> DATE '0001-01-01'
      AND greatest(ci.lower_day, anniversary.anniversary_day)
          <= least(ci.upper_day, anniversary.next_anniversary_day - 1)
), club_segments AS MATERIALIZED (
    SELECT * FROM club_unknown_age_segments
    UNION ALL
    SELECT * FROM club_known_age_segments
), network_unknown_age_segments AS (
    SELECT ci.is_child, ci.lower_day, ci.upper_day,
           NULL::smallint AS age_years, ca.gender
    FROM client_islands AS ci
    JOIN client_attributes AS ca USING (client_id)
    WHERE ca.birth_date IS NULL OR ca.birth_date = DATE '0001-01-01'
), network_known_age_segments AS (
    SELECT ci.is_child,
           greatest(ci.lower_day, anniversary.anniversary_day) AS lower_day,
           least(ci.upper_day, anniversary.next_anniversary_day - 1) AS upper_day,
           extract(year FROM age(
               greatest(ci.lower_day, anniversary.anniversary_day), ca.birth_date
           ))::smallint AS age_years,
           ca.gender
    FROM client_islands AS ci
    JOIN client_attributes AS ca USING (client_id)
    CROSS JOIN LATERAL generate_series(
        date_trunc('year', ci.lower_day)::date - INTERVAL '1 year',
        date_trunc('year', ci.upper_day)::date,
        INTERVAL '1 year'
    ) AS year_start
    CROSS JOIN LATERAL (
        SELECT (
                   ca.birth_date
                   + make_interval(
                       years => extract(year FROM year_start)::int
                              - extract(year FROM ca.birth_date)::int
                   )
               )::date AS anniversary_day,
               (
                   ca.birth_date
                   + make_interval(
                       years => extract(year FROM year_start)::int + 1
                              - extract(year FROM ca.birth_date)::int
                   )
               )::date AS next_anniversary_day
    ) AS anniversary
    WHERE ca.birth_date IS NOT NULL
      AND ca.birth_date <> DATE '0001-01-01'
      AND greatest(ci.lower_day, anniversary.anniversary_day)
          <= least(ci.upper_day, anniversary.next_anniversary_day - 1)
), network_segments AS MATERIALIZED (
    SELECT * FROM network_unknown_age_segments
    UNION ALL
    SELECT * FROM network_known_age_segments
), club_events AS (
    SELECT club_ref, is_child, age_years, gender, lower_day AS event_date, 1::bigint AS delta
    FROM club_segments
    UNION ALL
    SELECT club_ref, is_child, age_years, gender, upper_day + 1, -1::bigint
    FROM club_segments
), club_event_totals AS (
    SELECT club_ref, is_child, age_years, gender, event_date, sum(delta)::bigint AS delta
    FROM club_events
    GROUP BY club_ref, is_child, age_years, gender, event_date
), club_state AS (
    SELECT club_ref,
           is_child,
           age_years,
           gender,
           event_date,
           sum(delta) OVER (
               PARTITION BY club_ref, is_child, age_years, gender
               ORDER BY event_date
           ) AS client_count,
           lead(event_date) OVER (
               PARTITION BY club_ref, is_child, age_years, gender
               ORDER BY event_date
           ) AS next_event_date
    FROM club_event_totals
), club_daily AS (
    SELECT day::date AS report_date,
           club_ref,
           is_child,
           age_years,
           gender,
           client_count
    FROM club_state
    CROSS JOIN LATERAL generate_series(
        event_date,
        next_event_date - 1,
        INTERVAL '1 day'
    ) AS day
    WHERE client_count > 0
), network_events AS (
    SELECT is_child, age_years, gender, lower_day AS event_date, 1::bigint AS delta
    FROM network_segments
    UNION ALL
    SELECT is_child, age_years, gender, upper_day + 1, -1::bigint
    FROM network_segments
), network_event_totals AS (
    SELECT is_child, age_years, gender, event_date, sum(delta)::bigint AS delta
    FROM network_events
    GROUP BY is_child, age_years, gender, event_date
), network_state AS (
    SELECT is_child,
           age_years,
           gender,
           event_date,
           sum(delta) OVER (
               PARTITION BY is_child, age_years, gender
               ORDER BY event_date
           ) AS client_count,
           lead(event_date) OVER (
               PARTITION BY is_child, age_years, gender
               ORDER BY event_date
           ) AS next_event_date
    FROM network_event_totals
), network_daily AS (
    SELECT day::date AS report_date,
           is_child,
           age_years,
           gender,
           client_count
    FROM network_state
    CROSS JOIN LATERAL generate_series(
        event_date,
        next_event_date - 1,
        INTERVAL '1 day'
    ) AS day
    WHERE client_count > 0
), classified_club AS (
    SELECT 'club'::text AS scope_level,
           report_date,
           encode(club_ref, 'hex') AS club_id,
           age_years,
           CASE
               WHEN is_child THEN 'Дети'
               WHEN age_years IS NULL THEN 'Не указано'
               WHEN age_years < 14 THEN 'Дети'
               WHEN age_years < 18 THEN 'Юниоры'
               ELSE 'Взрослые'
           END AS age_group,
           gender,
           client_count
    FROM club_daily
    WHERE client_count > 0
), classified_network AS (
    SELECT 'network'::text AS scope_level,
           report_date,
           NULL::text AS club_id,
           age_years,
           CASE
               WHEN is_child THEN 'Дети'
               WHEN age_years IS NULL THEN 'Не указано'
               WHEN age_years < 14 THEN 'Дети'
               WHEN age_years < 18 THEN 'Юниоры'
               ELSE 'Взрослые'
           END AS age_group,
           gender,
           client_count
    FROM network_daily
    WHERE client_count > 0
), classified AS (
    SELECT scope_level,
           report_date,
           club_id,
           age_years,
           age_group,
           gender,
           client_count
    FROM classified_club
    UNION ALL
    SELECT scope_level,
           report_date,
           club_id,
           age_years,
           age_group,
           gender,
           client_count
    FROM classified_network
)
SELECT scope_level,
       report_date,
       club_id,
       age_years,
       age_group,
       gender,
       sum(client_count)::bigint AS client_count
FROM classified
GROUP BY scope_level, report_date, club_id, age_years, age_group, gender
ORDER BY scope_level, report_date, club_id NULLS FIRST, age_years NULLS FIRST, gender;
