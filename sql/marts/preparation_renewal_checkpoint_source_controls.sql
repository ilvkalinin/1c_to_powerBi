-- Independent source controls for mart.preparation_renewal_checkpoint.
-- $1/$2 are inclusive/exclusive checkpoint-date batch boundaries.
-- This is intentionally the legacy-M path: bucket then cumulative sums and
-- DAX-natural freeze matching, not the target extract's technical flag path.

WITH legacy_contracts AS MATERIALIZED (
    SELECT r._idrref AS contract_ref,
           r._description::text AS contract_name,
           client._code::text AS client_code,
           r._fld681rref AS client_ref,
           r._fld672::date AS membership_end_date
    FROM public._reference59 AS r
    JOIN public._reference141x1 AS client
      ON client._idrref = r._fld681rref
    JOIN public._reference132 AS club
      ON club._idrref = r._fld687rref
    WHERE r._code IS NOT NULL
      AND r._fld681rref <> decode('00000000000000000000000000000000', 'hex')
      AND r._fld672 >= DATE '2022-01-01'
      -- A contract can produce a batch checkpoint iff end_date is in this
      -- closed/open range; this is a source-side reduction only.
      AND r._fld672::date >= $1::date + 91
      AND r._fld672::date < $2::date + 114
      AND r._description::text NOT LIKE '%сотруд%'
      AND r._description::text NOT LIKE '%ИП%'
      AND r._fld696rref = decode('bf4b50662e88eb7b44046ebf4849976f', 'hex')
      AND r._fld672::date - r._fld671::date >= 30
      AND r._fld694rref = ANY (ARRAY[
          decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex'),
          decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex'),
          decode('9e369ac955bf602149e17b549b0f1498', 'hex')
      ])
), checkpoints AS MATERIALIZED (
    SELECT c.*, p.day::smallint AS checkpoint_day,
           (c.membership_end_date - 121 + p.day)::date AS checkpoint_date,
           CASE p.day WHEN 7 THEN 1 WHEN 14 THEN 2 WHEN 21 THEN 3
                      WHEN 28 THEN 4 WHEN 30 THEN 4 END::smallint AS target_visit_count
    FROM legacy_contracts AS c
    CROSS JOIN (VALUES (7), (14), (21), (28), (30)) AS p(day)
    WHERE c.membership_end_date - 121 + p.day >= $1::date
      AND c.membership_end_date - 121 + p.day < $2::date
), legacy_visit_buckets AS MATERIALIZED (
    SELECT c.contract_ref,
           CASE
               WHEN extract(day FROM (c.membership_end_date - a._period)) >= 113 THEN 7
               WHEN extract(day FROM (c.membership_end_date - a._period)) >= 106 THEN 14
               WHEN extract(day FROM (c.membership_end_date - a._period)) >= 99 THEN 21
               WHEN extract(day FROM (c.membership_end_date - a._period)) >= 92 THEN 28
               WHEN extract(day FROM (c.membership_end_date - a._period)) >= 90 THEN 30
           END::smallint AS bucket_day,
           count(*)::bigint AS visit_rows
    FROM legacy_contracts AS c
    JOIN public._accumrg7575 AS a
      ON a._fld7578_rrref = c.contract_ref
     AND a._fld7576rref = c.client_ref
    JOIN public._reference163 AS service
      ON service._idrref = a._fld7579rref
    WHERE a._period > c.membership_end_date - INTERVAL '120 days'
      AND a._period <= c.membership_end_date - INTERVAL '90 days'
      AND a._period >= $1::timestamp without time zone - INTERVAL '30 days'
      AND a._period < $2::timestamp without time zone + INTERVAL '2 days'
      AND service._description::text = 'посещение клуба'
      AND service._description::text NOT LIKE '%ИП%'
      AND service._description::text NOT LIKE '%Контракт сотрудника%'
    GROUP BY c.contract_ref, 2
), raw_freeze AS MATERIALIZED (
    SELECT f._fld7479rref AS contract_ref,
           contract._code AS contract_code,
           contract._description::text AS contract_name,
           freeze_client._code::text AS client_code,
           i._fld5862::date AS freeze_start_date,
           i._fld5863::date AS freeze_end_date,
           f._period,
           f._recordertref,
           f._recorderrref,
           f._lineno
    FROM public._accumrg7478 AS f
    JOIN public._inforg5859 AS i
      ON i._recorderrref = f._recorderrref
     AND i._fld5860rref = f._fld7479rref
    LEFT JOIN public._reference59 AS contract
      ON contract._idrref = f._fld7479rref
    LEFT JOIN public._reference141x1 AS freeze_client
      ON freeze_client._idrref = f._fld7480rref
    WHERE f._period > TIMESTAMP '2021-01-01'
      AND f._period < $2::timestamp without time zone
      AND f._recordkind = 1
      AND i._fld5862 IS NOT NULL
      AND i._fld5863::date <> i._fld5862::date
      AND i._fld5862::date < $2::date
      AND i._fld5863::date >= $1::date
), legacy_freeze AS MATERIALIZED (
    SELECT DISTINCT ON (contract_code, freeze_start_date)
           contract_name, client_code, freeze_start_date, freeze_end_date
    FROM raw_freeze
    ORDER BY contract_code, freeze_start_date,
             _period DESC, _recordertref, _recorderrref, _lineno DESC
), natural_freeze_flags AS MATERIALIZED (
    SELECT DISTINCT c.contract_ref, c.checkpoint_day
    FROM checkpoints AS c
    JOIN legacy_freeze AS f
      ON f.contract_name = c.contract_name
     AND f.client_code = c.client_code
     AND f.freeze_start_date <= c.checkpoint_date
     AND f.freeze_end_date >= c.checkpoint_date
), visit_points AS MATERIALIZED (
    SELECT c.contract_ref,
           c.checkpoint_day,
           c.checkpoint_date,
           coalesce(sum(v.visit_rows) FILTER (WHERE v.bucket_day <= c.checkpoint_day), 0)::bigint
               AS visit_count_to_checkpoint,
           c.target_visit_count
    FROM checkpoints AS c
    LEFT JOIN legacy_visit_buckets AS v
      ON v.contract_ref = c.contract_ref
    GROUP BY c.contract_ref, c.checkpoint_day, c.checkpoint_date,
             c.target_visit_count
), expected_points AS MATERIALIZED (
    SELECT p.*,
           (f.contract_ref IS NOT NULL) AS frozen_at_checkpoint_flag
    FROM visit_points AS p
    LEFT JOIN natural_freeze_flags AS f
      ON f.contract_ref = p.contract_ref
     AND f.checkpoint_day = p.checkpoint_day
)
SELECT count(*)::bigint AS expected_rows,
       coalesce(sum(visit_count_to_checkpoint), 0)::bigint AS expected_visit_count,
       count(*) FILTER (WHERE frozen_at_checkpoint_flag)::bigint AS expected_frozen_points,
       count(*) FILTER (WHERE visit_count_to_checkpoint < target_visit_count)::bigint
           AS expected_below_target_points,
       min(checkpoint_date) AS min_checkpoint_date,
       max(checkpoint_date) AS max_checkpoint_date
FROM expected_points;
