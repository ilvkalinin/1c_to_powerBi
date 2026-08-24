-- REVIEWED source-side extract for mart.preparation_renewal_checkpoint.
-- $1/$2 are inclusive/exclusive checkpoint-date batch boundaries.
-- The source session is REPEATABLE READ, READ ONLY.

-- name: checkpoint
WITH contract_base AS MATERIALIZED (
    SELECT r._idrref AS contract_ref,
           encode(r._idrref, 'hex') AS contract_id,
           r._code::text AS contract_code,
           r._fld681rref AS client_ref,
           encode(r._fld681rref, 'hex') AS client_id,
           r._fld671::date AS membership_start_date,
           r._fld672::date AS membership_end_date,
           encode(r._fld687rref, 'hex') AS access_club_id,
           club._description::text AS access_club_name,
           r._description::text AS contract_name,
           client._code::text AS client_code,
           CASE r._fld694rref
               WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex') THEN 'New'
               WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex') THEN 'Renew'
               WHEN decode('9e369ac955bf602149e17b549b0f1498', 'hex') THEN 'Ex'
           END AS membership_tenure,
           CASE
               WHEN client._fld1507::date = DATE '0001-01-01' THEN NULL
               WHEN extract(year FROM age(r._fld670::date, client._fld1507::date)) < 14 THEN 'Дети'
               WHEN extract(year FROM age(r._fld670::date, client._fld1507::date)) < 18 THEN 'Юниоры'
               ELSE 'Взрослые'
           END AS age_group
    FROM public._reference59 AS r
    JOIN public._reference141x1 AS client
      ON client._idrref = r._fld681rref
    JOIN public._reference132 AS club
      ON club._idrref = r._fld687rref
    WHERE r._code IS NOT NULL
      AND r._fld681rref <> decode('00000000000000000000000000000000', 'hex')
      AND r._fld672 >= DATE '2022-01-01'
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
           CASE p.day WHEN 7 THEN 113 WHEN 14 THEN 106 WHEN 21 THEN 99
                      WHEN 28 THEN 92 WHEN 30 THEN 90 END::smallint AS visit_day_threshold,
           CASE p.day WHEN 7 THEN 1 WHEN 14 THEN 2 WHEN 21 THEN 3
                      WHEN 28 THEN 4 WHEN 30 THEN 4 END::smallint AS target_visit_count
    FROM contract_base AS c
    CROSS JOIN (VALUES (7), (14), (21), (28), (30)) AS p(day)
    WHERE c.membership_end_date - 121 + p.day >= $1::date
      AND c.membership_end_date - 121 + p.day < $2::date
), eligible_contracts AS MATERIALIZED (
    SELECT DISTINCT contract_ref, client_ref, membership_end_date
    FROM checkpoints
), visit_events AS MATERIALIZED (
    SELECT a._fld7578_rrref AS contract_ref,
           a._period
    FROM public._accumrg7575 AS a
    JOIN eligible_contracts AS c
      ON c.contract_ref = a._fld7578_rrref
     AND c.client_ref = a._fld7576rref
    JOIN public._reference163 AS service
      ON service._idrref = a._fld7579rref
    WHERE a._period > c.membership_end_date - INTERVAL '120 days'
      AND a._period <= c.membership_end_date - INTERVAL '90 days'
      AND a._period >= $1::timestamp without time zone - INTERVAL '30 days'
      AND a._period < $2::timestamp without time zone + INTERVAL '2 days'
      AND service._description::text = 'посещение клуба'
      AND service._description::text NOT LIKE '%ИП%'
      AND service._description::text NOT LIKE '%Контракт сотрудника%'
), visit_counts AS MATERIALIZED (
    SELECT c.contract_ref,
           c.checkpoint_day,
           count(v._period)::integer AS visit_count_to_checkpoint
    FROM checkpoints AS c
    LEFT JOIN visit_events AS v
      ON v.contract_ref = c.contract_ref
     AND extract(day FROM (c.membership_end_date - v._period)) >= c.visit_day_threshold
    GROUP BY c.contract_ref, c.checkpoint_day
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
      AND f._period < TIMESTAMP '2027-01-01'
      AND f._recordkind = 1
      AND i._fld5862 IS NOT NULL
      AND i._fld5863::date <> i._fld5862::date
      AND i._fld5862::date < $2::date
      AND i._fld5863::date >= $1::date
), legacy_freeze AS MATERIALIZED (
    SELECT DISTINCT ON (contract_code, freeze_start_date)
           contract_ref, contract_name, client_code, freeze_start_date, freeze_end_date
    FROM raw_freeze
    ORDER BY contract_code, freeze_start_date,
             _period DESC, _recordertref, _recorderrref, _lineno DESC
), freeze_flags AS MATERIALIZED (
    SELECT DISTINCT c.contract_ref, c.checkpoint_day
    FROM checkpoints AS c
    JOIN legacy_freeze AS f
      ON f.contract_ref = c.contract_ref
     AND f.freeze_start_date <= c.checkpoint_date
     AND f.freeze_end_date >= c.checkpoint_date
)
SELECT c.contract_id,
       c.contract_code,
       c.client_id,
       c.membership_start_date,
       c.membership_end_date,
       c.access_club_id,
       c.access_club_name,
       c.checkpoint_day,
       c.checkpoint_date,
       vc.visit_count_to_checkpoint,
       CASE
           WHEN vc.visit_count_to_checkpoint >= 4 THEN '4+'
           ELSE vc.visit_count_to_checkpoint::text
       END AS visit_bucket,
       c.target_visit_count,
       (vc.visit_count_to_checkpoint < c.target_visit_count) AS below_target_flag,
       (ff.contract_ref IS NOT NULL) AS frozen_at_checkpoint_flag,
       c.age_group,
       c.membership_tenure
FROM checkpoints AS c
JOIN visit_counts AS vc
  ON vc.contract_ref = c.contract_ref
 AND vc.checkpoint_day = c.checkpoint_day
LEFT JOIN freeze_flags AS ff
  ON ff.contract_ref = c.contract_ref
 AND ff.checkpoint_day = c.checkpoint_day;
