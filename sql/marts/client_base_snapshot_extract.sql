-- Source-side aggregate for mart.client_base_snapshot.
-- Bind $1 = inclusive horizon start, $2 = exclusive horizon end.
-- BR-037/BR-038 are applied before club/network dedupe. No client ID leaves
-- the source: the final SELECT is already at the target grain.
WITH params AS (
    SELECT $1::date AS horizon_start, $2::date AS horizon_end
), report_dates AS MATERIALIZED (
    SELECT d::date AS report_date
    FROM params AS p,
         generate_series(p.horizon_start, p.horizon_end - 1, INTERVAL '1 day') AS d
    WHERE extract(isodow FROM d) = 1 OR extract(day FROM d) = 1
), membership_raw AS MATERIALIZED (
    SELECT ab._fld681rref AS client_id,
           ab._fld687rref AS club_ref,
           ab._fld671::date AS active_from,
           ab._fld672::date AS active_to
    FROM public._reference59 AS ab
    JOIN public._reference141x1 AS cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 AS club ON club._idrref = ab._fld687rref
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
    JOIN public._document346 AS d ON d._idrref = v._document346_idrref
    JOIN public._reference59 AS r ON r._idrref = v._fld4915rref
    JOIN public._reference141x1 AS child ON child._idrref = v._fld4916rref
    JOIN public._reference141x1 AS adult ON adult._idrref = r._fld681rref
    JOIN public._reference132 AS club ON club._idrref = r._fld687rref
    LEFT JOIN public._document346_vt4924 AS stock
      ON stock._document346_idrref = d._idrref
     AND stock._fld4929 = v._fld4917
    CROSS JOIN params AS p
    WHERE d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND r._fld672 > r._fld671
      -- Preserve the current source predicate pending a separately approved
      -- sentinel correction (BR-018); it is intentionally not normalised here.
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
), child_contracts AS MATERIALIZED (
    SELECT cr.contract_ref,
           cr.client_id,
           cr.club_ref,
           max(cr.candidate_start)::date AS active_from,
           max(cr.active_to)::date AS active_to
    FROM child_raw AS cr
    LEFT JOIN child_sales AS sale USING (receipt_ref, adult_ref, product_ref)
    CROSS JOIN params AS p
    WHERE sale.net_quantity IS NULL
       OR (sale.net_quantity > 0 AND sale.net_amount > 0)
    GROUP BY cr.contract_ref, cr.client_id, cr.club_ref, p.horizon_start, p.horizon_end
    HAVING max(cr.active_to)::date >= p.horizon_start - 1
       AND max(cr.candidate_start)::date < p.horizon_end
), club_candidates AS MATERIALIZED (
    SELECT d.report_date, m.client_id, m.club_ref, false AS is_child
    FROM report_dates AS d
    JOIN membership_raw AS m
      ON m.active_from < d.report_date
     AND m.active_to >= d.report_date - 1
    UNION ALL
    SELECT d.report_date, c.client_id, c.club_ref, true AS is_child
    FROM report_dates AS d
    JOIN child_contracts AS c
      ON c.active_from < d.report_date
     AND c.active_to >= d.report_date - 1
), club_scope AS MATERIALIZED (
    SELECT DISTINCT ON (report_date, club_ref, client_id)
           report_date, club_ref, client_id, is_child
    FROM club_candidates
    ORDER BY report_date, club_ref, client_id, is_child DESC
), network_scope AS MATERIALIZED (
    SELECT DISTINCT ON (report_date, client_id)
           report_date, client_id, is_child
    FROM club_scope
    ORDER BY report_date, client_id, is_child DESC
), client_dates AS MATERIALIZED (
    SELECT DISTINCT report_date, client_id
    FROM club_scope
    UNION
    SELECT report_date, client_id
    FROM network_scope
), qualified_visit_events AS MATERIALIZED (
    SELECT a._fld7576rref AS client_id,
           a._period
    FROM public._accumrg7575 AS a
    JOIN public._reference163 AS service
      ON service._idrref = a._fld7579rref
    CROSS JOIN params AS p
    WHERE a._period >= p.horizon_start::timestamp - INTERVAL '30 days'
      AND a._period < p.horizon_end::timestamp
      AND a._fld7585 <> 0
      AND service._description = 'посещение клуба'
), visit_counts AS MATERIALIZED (
    -- Read the bounded visit stream once, then apply its rows to the small
    -- report-date calendar. This avoids one 30-day source lookup per client.
    SELECT d.report_date,
           a.client_id,
           count(*)::bigint AS visit_count_30d
    FROM report_dates AS d
    JOIN qualified_visit_events AS a
      ON a._period >= d.report_date::timestamp - INTERVAL '30 days'
     AND a._period < d.report_date::timestamp
    GROUP BY d.report_date, a.client_id
), used_clients AS MATERIALIZED (
    SELECT DISTINCT client_id
    FROM client_dates
), client_static_attributes AS MATERIALIZED (
    SELECT u.client_id,
           cl._fld1507::date AS birth_date,
           CASE encode(cl._fld1527rref, 'hex')
               WHEN 'b64a5b1e2f68583046c1077a96a54ebd' THEN 'Женский'
               WHEN 'b26004420b2465b8457ffa23c30a12aa' THEN 'Мужской'
               ELSE 'Не указано'
           END AS gender
    FROM used_clients AS u
    JOIN public._reference141x1 AS cl ON cl._idrref = u.client_id
), tenure_history AS MATERIALIZED (
    -- A single source scan plus effective intervals replaces an as-of index
    -- probe for every client × report-date pair.
    SELECT h._fld5655rref AS client_id,
           h._period,
           CASE h._fld5656rref
               WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex') THEN 'New'
               WHEN decode('9e369ac955bf602149e17b549b0f1498', 'hex') THEN 'Ex'
               WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex') THEN 'Renew'
               ELSE 'Не указано'
           END::text AS membership_tenure,
           lead(h._period) OVER (
               PARTITION BY h._fld5655rref
               ORDER BY h._period, h._fld5656rref
           ) AS next_period
    FROM public._inforg5654 AS h
    JOIN used_clients AS u ON u.client_id = h._fld5655rref
), tenure_as_of AS MATERIALIZED (
    SELECT cd.report_date,
           cd.client_id,
           coalesce(h.membership_tenure, 'Не указано') AS membership_tenure
    FROM client_dates AS cd
    LEFT JOIN tenure_history AS h
      ON h.client_id = cd.client_id
     AND h._period < cd.report_date::timestamp
     AND (h.next_period IS NULL OR h.next_period >= cd.report_date::timestamp)
), client_attributes AS MATERIALIZED (
    SELECT cd.report_date,
           cd.client_id,
           cl.birth_date,
           cl.gender,
           tenure.membership_tenure,
           coalesce(visits.visit_count_30d, 0)::bigint AS visit_count_30d
    FROM client_dates AS cd
    JOIN client_static_attributes AS cl ON cl.client_id = cd.client_id
    JOIN tenure_as_of AS tenure
      ON tenure.report_date = cd.report_date
     AND tenure.client_id = cd.client_id
    LEFT JOIN visit_counts AS visits
      ON visits.report_date = cd.report_date
     AND visits.client_id = cd.client_id
), club_classified AS (
    SELECT 'club'::text AS scope_level,
           s.report_date,
           encode(s.club_ref, 'hex')::text AS club_id,
           CASE
               WHEN a.birth_date IS NULL OR a.birth_date = DATE '0001-01-01' THEN NULL::smallint
               ELSE extract(year FROM age(s.report_date, a.birth_date))::smallint
           END AS age_years,
           CASE
               WHEN s.is_child THEN 'Дети'
               WHEN a.birth_date IS NULL OR a.birth_date = DATE '0001-01-01' THEN 'Не указано'
               WHEN extract(year FROM age(s.report_date, a.birth_date)) < 14 THEN 'Дети'
               WHEN extract(year FROM age(s.report_date, a.birth_date)) < 18 THEN 'Юниоры'
               ELSE 'Взрослые'
           END::text AS age_group,
           a.gender,
           a.membership_tenure,
           CASE
               WHEN a.visit_count_30d = 0 THEN 'Не ходил'
               WHEN a.visit_count_30d = 1 THEN '1'
               WHEN a.visit_count_30d <= 3 THEN '2–3'
               WHEN a.visit_count_30d <= 7 THEN '4–7'
               ELSE '8+'
           END::text AS activity_bucket
    FROM club_scope AS s
    JOIN client_attributes AS a USING (report_date, client_id)
), network_classified AS (
    SELECT 'network'::text AS scope_level,
           s.report_date,
           NULL::text AS club_id,
           CASE
               WHEN a.birth_date IS NULL OR a.birth_date = DATE '0001-01-01' THEN NULL::smallint
               ELSE extract(year FROM age(s.report_date, a.birth_date))::smallint
           END AS age_years,
           CASE
               WHEN s.is_child THEN 'Дети'
               WHEN a.birth_date IS NULL OR a.birth_date = DATE '0001-01-01' THEN 'Не указано'
               WHEN extract(year FROM age(s.report_date, a.birth_date)) < 14 THEN 'Дети'
               WHEN extract(year FROM age(s.report_date, a.birth_date)) < 18 THEN 'Юниоры'
               ELSE 'Взрослые'
           END::text AS age_group,
           a.gender,
           a.membership_tenure,
           CASE
               WHEN a.visit_count_30d = 0 THEN 'Не ходил'
               WHEN a.visit_count_30d = 1 THEN '1'
               WHEN a.visit_count_30d <= 3 THEN '2–3'
               WHEN a.visit_count_30d <= 7 THEN '4–7'
               ELSE '8+'
           END::text AS activity_bucket
    FROM network_scope AS s
    JOIN client_attributes AS a USING (report_date, client_id)
), classified AS (
    SELECT * FROM club_classified
    UNION ALL
    SELECT * FROM network_classified
)
SELECT scope_level,
       report_date,
       club_id,
       age_years,
       age_group,
       gender,
       membership_tenure,
       activity_bucket,
       count(*)::bigint AS client_count
FROM classified
GROUP BY scope_level, report_date, club_id, age_years, age_group, gender,
         membership_tenure, activity_bucket
ORDER BY scope_level, report_date, club_id NULLS FIRST, age_years NULLS FIRST,
         age_group, gender, membership_tenure, activity_bucket;
