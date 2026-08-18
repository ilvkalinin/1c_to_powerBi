-- CB-V01..V03: exact current-M membership cohort; run in READ ONLY.
-- Expected: BR-005 excludes active_from = D, includes active_to = D-1;
-- club and network scopes are deduplicated independently.
WITH current_m AS (
 SELECT ab._fld681rref client_id, ab._fld687rref club_id,
        ab._fld671::date active_from, ab._fld672::date active_to, ab._marked
 FROM public._reference59 ab JOIN public._reference141x1 cl ON cl._idrref=ab._fld681rref
 JOIN public._reference132 club ON club._idrref=ab._fld687rref
 WHERE ab._fld672>=DATE '2021-01-01' AND ab._description::varchar NOT ILIKE '%сотруд%'
   AND ab._description::varchar NOT ILIKE '%ип%' AND ab._fld672>ab._fld671
   AND club._description::varchar<>'Детский развивающий центр'
   AND encode(ab._fld694rref,'hex') IN ('bc06e4b21430ebfb44a67a65c46d41f9','9e369ac955bf602149e17b549b0f1498','91e4594e35ce15d847c4a3f32e1e18f2')
), target AS (SELECT * FROM current_m WHERE active_from<DATE '2026-07-01' AND active_to>=DATE '2026-06-30')
SELECT count(*) raw_memberships, count(DISTINCT (club_id,client_id)) club_scope_clients,
 count(DISTINCT client_id) network_scope_clients, count(*) FILTER (WHERE _marked) marked_rows
FROM target;

-- CBD-V01A: prove that the confirmed membership source can form both daily
-- client-base scopes without an existing daily mart.  Run in READ ONLY.
-- Expected: every date in the stated seven-day control horizon has a non-empty
-- club and network cohort.  This validates source availability only; it does
-- not claim that mart.client_base_daily already exists or is loaded.
WITH control_dates AS (
    SELECT day::date AS report_date
    FROM generate_series(DATE '2026-07-01', DATE '2026-07-07', INTERVAL '1 day') AS day
), current_m AS (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_id,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 ab
    JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    WHERE ab._fld672 >= DATE '2021-01-01'
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND ab._fld672 > ab._fld671
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
), membership_by_day AS (
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

-- CBD-V04, CBD-V05: validate age and gender inputs used by the daily client
-- base on one control date.  The two non-null gender codes reproduce the
-- existing current-SQL mapping; any other non-null code is an exception, not
-- a new category.  Expected: no negative age and no unexpected non-null code.
WITH current_m AS (
    SELECT ab._fld681rref AS client_id,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 ab
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    WHERE ab._fld672 >= DATE '2021-01-01'
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND ab._fld672 > ab._fld671
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
), cohort AS (
    SELECT DISTINCT m.client_id,
           cl._fld1507::date AS birth_date,
           encode(cl._fld1527rref, 'hex') AS gender_code
    FROM current_m m
    JOIN public._reference141x1 cl ON cl._idrref = m.client_id
    WHERE m.active_from < DATE '2026-07-01'
      AND m.active_to >= DATE '2026-06-30'
), classified AS (
    SELECT *,
           CASE WHEN birth_date = DATE '0001-01-01' THEN NULL
                ELSE extract(year FROM age(DATE '2026-07-01', birth_date))::int
           END AS age_years
    FROM cohort
)
SELECT count(*) AS network_clients,
       count(*) FILTER (WHERE birth_date IS NULL) AS null_birth_date_clients,
       count(*) FILTER (WHERE birth_date = DATE '0001-01-01') AS sentinel_birth_date_clients,
       count(*) FILTER (WHERE age_years < 0) AS negative_age_clients,
       count(*) FILTER (WHERE age_years = 13) AS age_13_clients,
       count(*) FILTER (WHERE age_years = 14) AS age_14_clients,
       count(*) FILTER (WHERE age_years = 17) AS age_17_clients,
       count(*) FILTER (WHERE age_years = 18) AS age_18_clients,
       count(*) FILTER (WHERE gender_code = 'b64a5b1e2f68583046c1077a96a54ebd') AS female_clients,
       count(*) FILTER (WHERE gender_code = 'b26004420b2465b8457ffa23c30a12aa') AS male_clients,
       count(*) FILTER (WHERE gender_code IS NULL OR gender_code = '') AS null_gender_clients,
       count(*) FILTER (WHERE gender_code IS NOT NULL
                         AND gender_code NOT IN (
                            'b64a5b1e2f68583046c1077a96a54ebd',
                            'b26004420b2465b8457ffa23c30a12aa'
                         )) AS unexpected_nonnull_gender_clients
FROM classified;

-- CBD-V01B: inspect the exact two-year BR-003 interval join without executing
-- it.  Expected: a source plan is available; its estimates are not an SLA and
-- do not validate the daily mart.  The date predicates only remove memberships
-- that cannot overlap the requested calendar, so they do not change the cohort.
EXPLAIN (FORMAT JSON)
WITH control_dates AS (
    SELECT day::date AS report_date
    FROM generate_series(DATE '2025-01-01', DATE '2026-12-31', INTERVAL '1 day') AS day
), current_m AS (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_id,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 ab
    JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    WHERE ab._fld672 >= DATE '2021-01-01'
      AND ab._fld671 < DATE '2027-01-01'
      AND ab._fld672 >= DATE '2024-12-31'
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND ab._fld672 > ab._fld671
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
)
SELECT count(*)
FROM control_dates d
JOIN current_m m
  ON m.active_from < d.report_date
 AND m.active_to >= d.report_date - 1;

-- CBD-V01C: optimized 28-day execution control.  Expected: all calendar days
-- have a non-empty cohort in both scopes within the 30-second read-only limit.
-- The overlap predicates preserve the exact cohort while avoiding contracts
-- that cannot contribute to July 2026.
WITH control_dates AS (
    SELECT day::date AS report_date
    FROM generate_series(DATE '2026-07-01', DATE '2026-07-28', INTERVAL '1 day') AS day
), current_m AS (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_id,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 ab
    JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    WHERE ab._fld672 >= DATE '2021-01-01'
      AND ab._fld671 < DATE '2026-07-29'
      AND ab._fld672 >= DATE '2026-06-30'
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND ab._fld672 > ab._fld671
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
), membership_by_day AS (
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
