-- Read-only controls for client-base child-package coverage.
-- Execute each statement in REPEATABLE READ READ ONLY.  No client identifier,
-- name, code or PII is selected.  The package predicate deliberately
-- reproduces the observed current branch; it does not apply BR-037.

-- CB-PKG-001: representative current snapshot, 2026-08-25.
WITH params AS (SELECT DATE '2026-08-25' AS snapshot_date),
membership AS MATERIALIZED (
    SELECT ab._fld681rref AS client_ref, ab._fld687rref AS club_ref
    FROM public._reference59 ab
    JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    JOIN public._reference132 club ON club._idrref = ab._fld687rref
    CROSS JOIN params p
    WHERE ab._fld672 >= p.snapshot_date - 1
      AND ab._fld671 < p.snapshot_date
      AND ab._fld672 > ab._fld671
      AND ab._description::varchar NOT ILIKE '%сотруд%'
      AND ab._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND encode(ab._fld694rref, 'hex') IN (
          'bc06e4b21430ebfb44a67a65c46d41f9',
          '9e369ac955bf602149e17b549b0f1498',
          '91e4594e35ce15d847c4a3f32e1e18f2')
), package_raw AS MATERIALIZED (
    SELECT v._document346_idrref AS receipt_ref, v._lineno4914 AS line_no,
           child._idrref AS child_ref, r._fld687rref AS club_ref,
           greatest(r._fld671::date, d._date_time::date) AS package_start,
           r._fld672::date AS package_end
    FROM public._document346_vt4913 v
    JOIN public._document346 d ON d._idrref = v._document346_idrref
    JOIN public._reference59 r ON r._idrref = v._fld4915rref
    JOIN public._reference141x1 child ON child._idrref = v._fld4916rref
    JOIN public._reference141x1 adult ON adult._idrref = r._fld681rref
    JOIN public._reference132 club ON club._idrref = r._fld687rref
    CROSS JOIN params p
    WHERE d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND r._fld672 > r._fld671
      AND (r._fld670 IS NOT NULL OR r._fld670 <> TIMESTAMP '0001-01-01 00:00:00')
      AND r._fld681rref IS NOT NULL
      AND child._code IS NOT NULL
      AND club._description IS NOT NULL
      AND r._description::varchar NOT ILIKE '%сотруд%'
      AND r._description::varchar NOT ILIKE '%ип%'
      AND club._description::varchar <> 'Детский развивающий центр'
      AND greatest(r._fld671::date, d._date_time::date) < p.snapshot_date
      AND r._fld672 >= p.snapshot_date - 1
), package_club AS MATERIALIZED (
    SELECT DISTINCT child_ref, club_ref FROM package_raw
), package_network AS MATERIALIZED (
    SELECT DISTINCT child_ref FROM package_raw
)
SELECT 'membership_club'::text AS control, count(DISTINCT (client_ref, club_ref))::bigint AS value
FROM membership
UNION ALL SELECT 'membership_network', count(DISTINCT client_ref)::bigint FROM membership
UNION ALL SELECT 'package_club', count(*)::bigint FROM package_club
UNION ALL SELECT 'package_network', count(*)::bigint FROM package_network
UNION ALL
SELECT 'package_only_club', count(*)::bigint
FROM package_club p LEFT JOIN membership m ON m.client_ref = p.child_ref AND m.club_ref = p.club_ref
WHERE m.client_ref IS NULL
UNION ALL
SELECT 'package_only_network', count(*)::bigint
FROM package_network p LEFT JOIN membership m ON m.client_ref = p.child_ref
WHERE m.client_ref IS NULL;

-- CB-PKG-002: full BR-003 horizon.  It deliberately aggregates to two scope
-- controls rather than emitting daily or client-level detail.
WITH params AS (SELECT DATE '2025-01-01' AS horizon_start, DATE '2027-01-01' AS horizon_end),
calendar AS MATERIALIZED (
  SELECT day::date AS snapshot_date
  FROM params, generate_series(horizon_start, horizon_end - 1, interval '1 day') AS day
), membership_ranges AS MATERIALIZED (
  SELECT ab._fld681rref AS client_ref, ab._fld687rref AS club_ref,
         ab._fld671::date AS active_from, ab._fld672::date AS active_to
  FROM public._reference59 ab
  JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
  JOIN public._reference132 club ON club._idrref = ab._fld687rref
  CROSS JOIN params p
  WHERE ab._fld672 >= p.horizon_start - 1 AND ab._fld671 < p.horizon_end
    AND ab._fld672 > ab._fld671
    AND ab._description::varchar NOT ILIKE '%сотруд%'
    AND ab._description::varchar NOT ILIKE '%ип%'
    AND club._description::varchar <> 'Детский развивающий центр'
    AND encode(ab._fld694rref, 'hex') IN (
      'bc06e4b21430ebfb44a67a65c46d41f9',
      '9e369ac955bf602149e17b549b0f1498',
      '91e4594e35ce15d847c4a3f32e1e18f2')
), package_ranges AS MATERIALIZED (
  SELECT DISTINCT child._idrref AS child_ref, r._fld687rref AS club_ref,
         greatest(r._fld671::date, d._date_time::date) AS active_from,
         r._fld672::date AS active_to
  FROM public._document346_vt4913 v
  JOIN public._document346 d ON d._idrref = v._document346_idrref
  JOIN public._reference59 r ON r._idrref = v._fld4915rref
  JOIN public._reference141x1 child ON child._idrref = v._fld4916rref
  JOIN public._reference141x1 adult ON adult._idrref = r._fld681rref
  JOIN public._reference132 club ON club._idrref = r._fld687rref
  CROSS JOIN params p
  WHERE d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
    AND r._fld672 > r._fld671
    AND (r._fld670 IS NOT NULL OR r._fld670 <> TIMESTAMP '0001-01-01 00:00:00')
    AND r._fld681rref IS NOT NULL AND child._code IS NOT NULL
    AND club._description IS NOT NULL
    AND r._description::varchar NOT ILIKE '%сотруд%'
    AND r._description::varchar NOT ILIKE '%ип%'
    AND club._description::varchar <> 'Детский развивающий центр'
    AND greatest(r._fld671::date, d._date_time::date) < p.horizon_end
    AND r._fld672 >= p.horizon_start - 1
), package_only_club_by_day AS MATERIALIZED (
  SELECT c.snapshot_date, p.child_ref, p.club_ref
  FROM calendar c JOIN package_ranges p
    ON p.active_from < c.snapshot_date AND p.active_to >= c.snapshot_date - 1
  WHERE NOT EXISTS (
    SELECT 1 FROM membership_ranges m
    WHERE m.client_ref = p.child_ref AND m.club_ref = p.club_ref
      AND m.active_from < c.snapshot_date AND m.active_to >= c.snapshot_date - 1)
  GROUP BY c.snapshot_date, p.child_ref, p.club_ref
), package_only_network_by_day AS MATERIALIZED (
  SELECT c.snapshot_date, p.child_ref
  FROM calendar c JOIN package_ranges p
    ON p.active_from < c.snapshot_date AND p.active_to >= c.snapshot_date - 1
  WHERE NOT EXISTS (
    SELECT 1 FROM membership_ranges m
    WHERE m.client_ref = p.child_ref
      AND m.active_from < c.snapshot_date AND m.active_to >= c.snapshot_date - 1)
  GROUP BY c.snapshot_date, p.child_ref
), club_daily AS (
  SELECT snapshot_date, count(*)::bigint AS package_only_count
  FROM package_only_club_by_day GROUP BY snapshot_date
), network_daily AS (
  SELECT snapshot_date, count(*)::bigint AS package_only_count
  FROM package_only_network_by_day GROUP BY snapshot_date
)
SELECT 'club'::text AS scope_level, count(*)::bigint AS days_with_gap,
       coalesce(sum(package_only_count), 0)::bigint AS package_only_client_days,
       coalesce(max(package_only_count), 0)::bigint AS max_daily_gap
FROM club_daily
UNION ALL
SELECT 'network', count(*), coalesce(sum(package_only_count), 0), coalesce(max(package_only_count), 0)
FROM network_daily
ORDER BY scope_level;

-- CB-PKG-003: physical integrity and observed source states.  No state filter
-- is introduced; these counts document the current package branch boundary.
SELECT
  count(*)::bigint AS vt_rows,
  count(DISTINCT (v._document346_idrref, v._lineno4914))::bigint AS technical_keys,
  count(*) FILTER (WHERE d._idrref IS NULL)::bigint AS missing_receipt,
  count(*) FILTER (WHERE r._idrref IS NULL)::bigint AS missing_contract,
  count(*) FILTER (WHERE child._idrref IS NULL)::bigint AS missing_child,
  count(*) FILTER (WHERE adult._idrref IS NULL)::bigint AS missing_adult,
  count(*) FILTER (WHERE club._idrref IS NULL)::bigint AS missing_club,
  count(*) FILTER (WHERE d._marked)::bigint AS receipt_marked,
  count(*) FILTER (WHERE NOT d._posted)::bigint AS receipt_unposted,
  count(*) FILTER (WHERE d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex'))::bigint AS current_status_rows,
  count(*) FILTER (WHERE r._fld670 IS NULL OR r._fld670 = TIMESTAMP '0001-01-01 00:00:00')::bigint AS activation_null_or_sentinel,
  count(*) FILTER (WHERE r._fld672 <= r._fld671)::bigint AS invalid_contract_interval
FROM public._document346_vt4913 v
LEFT JOIN public._document346 d ON d._idrref = v._document346_idrref
LEFT JOIN public._reference59 r ON r._idrref = v._fld4915rref
LEFT JOIN public._reference141x1 child ON child._idrref = v._fld4916rref
LEFT JOIN public._reference141x1 adult ON adult._idrref = r._fld681rref
LEFT JOIN public._reference132 club ON club._idrref = r._fld687rref;
