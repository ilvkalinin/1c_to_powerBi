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
), current_membership AS MATERIALIZED (
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
    SELECT ci.club_ref, ci.lower_day, ci.upper_day,
           NULL::smallint AS age_years, ca.gender
    FROM club_islands AS ci
    JOIN client_attributes AS ca USING (client_id)
    WHERE ca.birth_date IS NULL OR ca.birth_date = DATE '0001-01-01'
), club_known_age_segments AS (
    SELECT ci.club_ref,
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
    SELECT ci.lower_day, ci.upper_day,
           NULL::smallint AS age_years, ca.gender
    FROM client_islands AS ci
    JOIN client_attributes AS ca USING (client_id)
    WHERE ca.birth_date IS NULL OR ca.birth_date = DATE '0001-01-01'
), network_known_age_segments AS (
    SELECT greatest(ci.lower_day, anniversary.anniversary_day) AS lower_day,
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
    SELECT club_ref, age_years, gender, lower_day AS event_date, 1::bigint AS delta
    FROM club_segments
    UNION ALL
    SELECT club_ref, age_years, gender, upper_day + 1, -1::bigint
    FROM club_segments
), club_event_totals AS (
    SELECT club_ref, age_years, gender, event_date, sum(delta)::bigint AS delta
    FROM club_events
    GROUP BY club_ref, age_years, gender, event_date
), club_state AS (
    SELECT club_ref,
           age_years,
           gender,
           event_date,
           sum(delta) OVER (
               PARTITION BY club_ref, age_years, gender
               ORDER BY event_date
           ) AS client_count,
           lead(event_date) OVER (
               PARTITION BY club_ref, age_years, gender
               ORDER BY event_date
           ) AS next_event_date
    FROM club_event_totals
), club_daily AS (
    SELECT day::date AS report_date,
           club_ref,
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
    SELECT age_years, gender, lower_day AS event_date, 1::bigint AS delta
    FROM network_segments
    UNION ALL
    SELECT age_years, gender, upper_day + 1, -1::bigint
    FROM network_segments
), network_event_totals AS (
    SELECT age_years, gender, event_date, sum(delta)::bigint AS delta
    FROM network_events
    GROUP BY age_years, gender, event_date
), network_state AS (
    SELECT age_years,
           gender,
           event_date,
           sum(delta) OVER (
               PARTITION BY age_years, gender
               ORDER BY event_date
           ) AS client_count,
           lead(event_date) OVER (
               PARTITION BY age_years, gender
               ORDER BY event_date
           ) AS next_event_date
    FROM network_event_totals
), network_daily AS (
    SELECT day::date AS report_date,
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
               WHEN age_years IS NULL THEN 'Не указано'
               WHEN age_years < 14 THEN 'Дети'
               WHEN age_years < 18 THEN 'Юниоры'
               ELSE 'Взрослые'
           END AS age_group,
           gender,
           client_count
    FROM network_daily
    WHERE client_count > 0
)
SELECT scope_level,
       report_date,
       club_id,
       age_years,
       age_group,
       gender,
       client_count::bigint
FROM classified_club
UNION ALL
SELECT scope_level,
       report_date,
       club_id,
       age_years,
       age_group,
       gender,
       client_count::bigint
FROM classified_network
ORDER BY scope_level, report_date, club_id NULLS FIRST, age_years NULLS FIRST, gender;
