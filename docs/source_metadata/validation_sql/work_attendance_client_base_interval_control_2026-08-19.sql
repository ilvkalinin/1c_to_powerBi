-- WA-V06C: interval-equivalent full BR-003 client-base control.
-- The rule is unchanged: a membership is active on D iff active_from < D and
-- active_to >= D - 1.  The query first merges overlapping intervals per
-- client × club and per client, then counts their daily coverage.
-- Expected before execution:
--   * 730 nonempty dates in both club and network scopes;
--   * on four anchor dates, interval counts equal the direct current-M
--     COUNT(DISTINCT) calculation exactly (difference = 0);
--   * output is aggregated only and is not an end-to-end refresh SLA.

BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

WITH params AS (
    SELECT DATE '2025-01-01' AS first_day, DATE '2026-12-31' AS last_day
), control_dates AS MATERIALIZED (
    SELECT day::date AS report_date
    FROM params, generate_series(first_day, last_day, INTERVAL '1 day') AS day
), current_m AS MATERIALIZED (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_id,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 ab
    JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    CROSS JOIN params p
    WHERE ab._fld672 >= p.first_day - 1
      AND ab._fld671 < p.last_day
      AND ab._fld672 > ab._fld671
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
), club_ranges AS MATERIALIZED (
    SELECT client_id, club_id,
           greatest(active_from + 1, p.first_day) AS lower_day,
           least(active_to + 1, p.last_day) AS upper_day
    FROM current_m CROSS JOIN params p
), club_ordered AS (
    SELECT *, max(upper_day) OVER (
        PARTITION BY client_id, club_id
        ORDER BY lower_day, upper_day
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS previous_upper_day
    FROM club_ranges
), club_numbered AS (
    SELECT *, sum(CASE WHEN previous_upper_day IS NULL
                             OR lower_day > previous_upper_day + 1
                        THEN 1 ELSE 0 END) OVER (
        PARTITION BY client_id, club_id ORDER BY lower_day, upper_day
    ) AS island_id
    FROM club_ordered
), club_islands AS MATERIALIZED (
    SELECT client_id, club_id, island_id,
           min(lower_day) AS lower_day, max(upper_day) AS upper_day
    FROM club_numbered
    GROUP BY client_id, club_id, island_id
), client_ranges AS MATERIALIZED (
    SELECT client_id,
           greatest(active_from + 1, p.first_day) AS lower_day,
           least(active_to + 1, p.last_day) AS upper_day
    FROM current_m CROSS JOIN params p
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
        PARTITION BY client_id ORDER BY lower_day, upper_day
    ) AS island_id
    FROM client_ordered
), client_islands AS MATERIALIZED (
    SELECT client_id, island_id,
           min(lower_day) AS lower_day, max(upper_day) AS upper_day
    FROM client_numbered
    GROUP BY client_id, island_id
), club_events AS (
    SELECT club_id, lower_day AS report_date, 1::bigint AS delta FROM club_islands
    UNION ALL
    SELECT club_id, upper_day + 1, -1::bigint FROM club_islands
), club_daily AS (
    SELECT report_date, club_id,
           sum(delta) OVER (PARTITION BY club_id ORDER BY report_date) AS active_clients
    FROM (
        SELECT d.report_date, c.club_id, coalesce(sum(e.delta), 0)::bigint AS delta
        FROM control_dates d
        CROSS JOIN (SELECT DISTINCT club_id FROM club_islands) c
        LEFT JOIN club_events e ON e.report_date = d.report_date AND e.club_id = c.club_id
        GROUP BY d.report_date, c.club_id
    ) events_by_day
), network_events AS (
    SELECT lower_day AS report_date, 1::bigint AS delta FROM client_islands
    UNION ALL
    SELECT upper_day + 1, -1::bigint FROM client_islands
), network_events_by_day AS (
    SELECT d.report_date, coalesce(sum(e.delta), 0)::bigint AS delta
    FROM control_dates d
    LEFT JOIN network_events e ON e.report_date = d.report_date
    GROUP BY d.report_date
), network_daily AS (
    SELECT report_date,
           sum(delta) OVER (ORDER BY report_date) AS active_clients
    FROM network_events_by_day
), interval_daily AS MATERIALIZED (
    SELECT d.report_date,
           coalesce(sum(cd.active_clients), 0)::bigint AS club_scope_clients,
           max(nd.active_clients)::bigint AS network_scope_clients
    FROM control_dates d
    LEFT JOIN club_daily cd ON cd.report_date = d.report_date
    LEFT JOIN network_daily nd ON nd.report_date = d.report_date
    GROUP BY d.report_date
), anchors(report_date) AS (
    VALUES (DATE '2025-01-01'), (DATE '2025-07-15'),
           (DATE '2026-01-01'), (DATE '2026-07-15')
), direct_anchor AS (
    SELECT a.report_date,
           count(DISTINCT (m.club_id, m.client_id))::bigint AS club_scope_clients,
           count(DISTINCT m.client_id)::bigint AS network_scope_clients
    FROM anchors a
    LEFT JOIN current_m m
      ON m.active_from < a.report_date
     AND m.active_to >= a.report_date - 1
    GROUP BY a.report_date
), anchor_comparison AS (
    SELECT i.report_date,
           i.club_scope_clients - d.club_scope_clients AS club_difference,
           i.network_scope_clients - d.network_scope_clients AS network_difference
    FROM interval_daily i
    JOIN direct_anchor d ON d.report_date = i.report_date
), anchor_control AS (
    SELECT count(*) FILTER (WHERE club_difference <> 0 OR network_difference <> 0)
               AS anchor_dates_with_difference
    FROM anchor_comparison
)
SELECT count(*) AS calendar_days,
       count(*) FILTER (WHERE club_scope_clients > 0) AS days_with_club_scope,
       count(*) FILTER (WHERE network_scope_clients > 0) AS days_with_network_scope,
       min(club_scope_clients) AS min_club_scope_clients,
       max(club_scope_clients) AS max_club_scope_clients,
       min(network_scope_clients) AS min_network_scope_clients,
       max(network_scope_clients) AS max_network_scope_clients,
       max(anchor_dates_with_difference) AS anchor_dates_with_difference
FROM interval_daily
CROSS JOIN anchor_control;

ROLLBACK;
