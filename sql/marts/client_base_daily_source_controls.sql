-- Independent source control for mart.client_base_daily.
-- Bind $1 = inclusive BR-003 horizon start, $2 = exclusive horizon end.
-- It uses merged membership intervals and daily deltas, not the extract's
-- client-day demographic expansion. Expected: one positive total per day and
-- scope; its totals must equal the sum of the staged aggregate rows exactly.
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
