-- S3-IP-REVENUE-001 — read-only source controls for mart.ip_revenue_daily.
-- Dynamic BR-003 horizon; execute in REPEATABLE READ, READ ONLY.

WITH calendar_bounds AS (
    SELECT CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 1 AND 3
                THEN (date_trunc('year', CURRENT_DATE) - INTERVAL '2 years')::date
                ELSE (date_trunc('year', CURRENT_DATE) - INTERVAL '1 year')::date
           END AS date_from,
           (date_trunc('year', CURRENT_DATE) + INTERVAL '1 year')::date AS date_to
), qualified AS (
    SELECT r._recordertref, r._recorderrref, r._lineno, r._active,
           r._period::date AS revenue_date,
           CASE WHEN club._idrref IS NULL THEN NULL ELSE encode(r._fld7372rref, 'hex') END AS club_id,
           encode(c._fld685rref, 'hex') AS service_id,
           r._fld7377::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7370 r
    JOIN public._reference59 c ON c._idrref = r._fld7371rref
    JOIN public._reference163 s ON s._idrref = c._fld685rref
    LEFT JOIN public._reference132 club ON club._idrref = r._fld7372rref
    CROSS JOIN calendar_bounds b
    WHERE r._period >= b.date_from
      AND r._period < b.date_to
      AND r._recordkind = 0
      AND CAST(s._description AS varchar(1000)) LIKE '%ИП%'
), grouped AS (
    SELECT revenue_date, club_id, service_id,
           sum(revenue_amount)::numeric(18, 2) AS revenue_amount
    FROM qualified
    GROUP BY 1, 2, 3
)
SELECT
    (SELECT count(*) FROM qualified)::bigint AS source_rows,
    (SELECT count(*) FROM grouped)::bigint AS target_grain_rows,
    (SELECT coalesce(sum(revenue_amount), 0)::numeric(18, 2) FROM qualified) AS source_revenue,
    (SELECT coalesce(sum(revenue_amount), 0)::numeric(18, 2) FROM grouped) AS grouped_revenue,
    (SELECT count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) FROM qualified)::bigint AS duplicate_technical_keys,
    (SELECT count(*) FILTER (WHERE NOT _active) FROM qualified)::bigint AS inactive_rows,
    (SELECT count(*) FILTER (WHERE club_id IS NULL) FROM grouped)::bigint AS null_club_target_rows,
    (SELECT count(*) FILTER (WHERE revenue_amount = 0) FROM grouped)::bigint AS zero_revenue_target_rows,
    (SELECT coalesce(sum(revenue_amount) FILTER (WHERE club_id IS NULL), 0)::numeric(18, 2) FROM grouped) AS null_club_revenue;
