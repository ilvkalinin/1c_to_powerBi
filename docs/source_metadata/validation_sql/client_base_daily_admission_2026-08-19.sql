-- S3-CBD-ADMISSION-001 — read-only compact-grain control.
-- Four independent anchor dates; validates the proposed daily target shape,
-- not an initial load. Run only on the source in REPEATABLE READ, READ ONLY.

WITH control_dates(report_date) AS (
    VALUES (DATE '2025-01-01'), (DATE '2025-07-15'),
           (DATE '2026-01-01'), (DATE '2026-07-15')
), current_m AS (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_id,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 ab
    JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    WHERE ab._fld672 >= DATE '2024-12-31'
      AND ab._fld671 < DATE '2026-07-15'
      AND ab._fld672 > ab._fld671
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2'
      )
), club_clients AS (
    SELECT DISTINCT d.report_date, m.club_id, m.client_id
    FROM control_dates d
    JOIN current_m m ON m.active_from < d.report_date
                    AND m.active_to >= d.report_date - 1
), network_clients AS (
    SELECT DISTINCT report_date, client_id FROM club_clients
), demographic_input AS (
    SELECT 'club'::text AS scope_level, cc.report_date,
           encode(cc.club_id, 'hex') AS club_id, cc.client_id,
           CASE WHEN cl._fld1507::date = DATE '0001-01-01' THEN NULL
                ELSE extract(year FROM age(cc.report_date, cl._fld1507::date))::smallint END AS age_years,
           encode(cl._fld1527rref, 'hex') AS gender_code
    FROM club_clients cc JOIN public._reference141x1 cl ON cl._idrref = cc.client_id
    UNION ALL
    SELECT 'network', nc.report_date, NULL, nc.client_id,
           CASE WHEN cl._fld1507::date = DATE '0001-01-01' THEN NULL
                ELSE extract(year FROM age(nc.report_date, cl._fld1507::date))::smallint END,
           encode(cl._fld1527rref, 'hex')
    FROM network_clients nc JOIN public._reference141x1 cl ON cl._idrref = nc.client_id
), daily_fact AS (
    SELECT scope_level, report_date, club_id, age_years,
           CASE WHEN age_years IS NULL THEN 'Не указано'
                WHEN age_years < 14 THEN 'Дети'
                WHEN age_years < 18 THEN 'Юниоры'
                ELSE 'Взрослые' END AS age_group,
           CASE gender_code
                WHEN 'b64a5b1e2f68583046c1077a96a54ebd' THEN 'Женский'
                WHEN 'b26004420b2465b8457ffa23c30a12aa' THEN 'Мужской'
                ELSE 'Не указано' END AS gender,
           count(*)::bigint AS client_count
    FROM demographic_input
    GROUP BY scope_level, report_date, club_id, age_years, gender_code
), expected AS (
    SELECT report_date, 'club'::text AS scope_level, count(*)::bigint AS client_count
    FROM club_clients GROUP BY report_date
    UNION ALL
    SELECT report_date, 'network', count(*)::bigint FROM network_clients GROUP BY report_date
), actual AS (
    SELECT report_date, scope_level, sum(client_count)::bigint AS client_count
    FROM daily_fact GROUP BY report_date, scope_level
), checks AS (
    SELECT count(*) FILTER (WHERE e.client_count <> a.client_count) AS total_mismatches
    FROM expected e JOIN actual a USING (report_date, scope_level)
)
SELECT
    (SELECT count(*) FROM daily_fact) AS target_grain_rows,
    (SELECT count(*) FILTER (WHERE scope_level = 'club' AND club_id IS NULL) FROM daily_fact) AS null_club_rows,
    (SELECT count(*) FILTER (WHERE scope_level = 'network' AND club_id IS NOT NULL) FROM daily_fact) AS network_with_club_rows,
    (SELECT count(*) FILTER (WHERE age_group IS NULL OR gender IS NULL OR client_count <= 0) FROM daily_fact) AS contract_violations,
    (SELECT total_mismatches FROM checks) AS control_sum_mismatches;
