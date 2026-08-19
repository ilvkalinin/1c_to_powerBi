-- WA-V06B: exact full BR-003 client-base history for «Работа с посещаемостью».
-- Runs on gymdb as gymdb_readonly in one REPEATABLE READ, READ ONLY snapshot.
-- Expected before execution:
--   * all 730 calendar dates 2025-01-01—2026-12-31 have nonempty club and
--     network cohorts under the current-M conditions;
--   * the daily query returns one row per calendar date and no raw client IDs;
--   * a completed read is source evidence only, not a mart-refresh SLA.

BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

WITH control_dates AS MATERIALIZED (
    SELECT day::date AS report_date
    FROM generate_series(DATE '2025-01-01', DATE '2026-12-31', INTERVAL '1 day') AS day
), current_m AS MATERIALIZED (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_id,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 ab
    JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    WHERE ab._fld672 >= DATE '2024-12-31'
      AND ab._fld671 < DATE '2027-01-01'
      AND ab._fld672 > ab._fld671
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
), membership_by_day AS MATERIALIZED (
    SELECT d.report_date, m.club_id, m.client_id
    FROM control_dates d
    JOIN current_m m
      ON m.active_from < d.report_date
     AND m.active_to >= d.report_date - 1
), daily_scope AS (
    SELECT d.report_date,
           count(DISTINCT (m.club_id, m.client_id)) AS club_scope_clients,
           count(DISTINCT m.client_id) AS network_scope_clients
    FROM control_dates d
    LEFT JOIN membership_by_day m ON m.report_date = d.report_date
    GROUP BY d.report_date
)
SELECT count(*) AS calendar_days,
       count(*) FILTER (WHERE club_scope_clients > 0) AS days_with_club_scope,
       count(*) FILTER (WHERE network_scope_clients > 0) AS days_with_network_scope,
       min(club_scope_clients) AS min_club_scope_clients,
       max(club_scope_clients) AS max_club_scope_clients,
       min(network_scope_clients) AS min_network_scope_clients,
       max(network_scope_clients) AS max_network_scope_clients
FROM daily_scope;

ROLLBACK;
