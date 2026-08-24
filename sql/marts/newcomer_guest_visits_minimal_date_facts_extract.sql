-- REVIEWED source extracts. Both sections execute in the same REPEATABLE READ
-- READ ONLY snapshot. $1 is the inclusive BR-003 timestamp; $2 is exclusive.

-- name: first_visit
WITH qualifying_visits AS MATERIALIZED (
    SELECT a._fld7578_rrref AS contract_id,
           a._period::date AS visit_date
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d
      ON d._idrref = a._recorderrref
    JOIN public._reference59 AS contract
      ON contract._idrref = a._fld7578_rrref
    JOIN public._reference141x1 AS client
      ON client._idrref = d._fld4171rref
    JOIN public._reference132 AS club
      ON club._idrref = d._fld4167rref
    WHERE a._period >= $1::timestamp without time zone
      AND a._period < $2::timestamp without time zone
      AND contract._fld694rref = decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex')
      AND d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND contract._description IS NOT NULL
      AND contract._description::text NOT ILIKE '%ИП%'
      AND contract._description::text NOT ILIKE '%сотрудн%'
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
)
SELECT encode(contract_id, 'hex') AS contract_id,
       min(visit_date) AS first_visit_date
FROM qualifying_visits
GROUP BY contract_id;

-- name: guest_visit_conversion
WITH guest_days AS MATERIALIZED (
    SELECT DISTINCT g._fld7065rref AS client_id,
           client._code::text AS client_code,
           g._fld7068::date AS guest_visit_date
    FROM public._inforg7064 AS g
    JOIN public._document325 AS visit_document
      ON visit_document._idrref = g._recorderrref
    LEFT JOIN public._reference141x1 AS client
      ON client._idrref = g._fld7065rref
    WHERE g._period >= $1::timestamp without time zone
      AND g._period < $2::timestamp without time zone
      AND g._fld7068 IS NOT NULL
), accuniq_groups AS MATERIALIZED (
    SELECT a._period::date AS accuniq_date,
           a._fld7576rref AS client_id,
           service._code::text AS service_code,
           a._fld7577rref AS club_id,
           sum(CASE WHEN a._fld7585 = -1 THEN -1 ELSE 1 END) AS signed_total
    FROM public._accumrg7575 AS a
    JOIN public._reference163 AS service
      ON service._idrref = a._fld7579rref
    WHERE a._period >= $1::timestamp without time zone
      AND a._period < $2::timestamp without time zone
      AND service._code::text IN (
          '00000017896', '00000018151', '00000017882', '00000017883',
          '00000018152', '00000017897', '00000016715', '00000016162',
          '00000016194', '00000016161', '00000017672', '00000016160'
      )
    GROUP BY 1, 2, 3, 4
), accuniq_days AS MATERIALIZED (
    SELECT DISTINCT client_id, accuniq_date
    FROM accuniq_groups
    WHERE signed_total IN (1, 2)
), suitable_contracts AS MATERIALIZED (
    SELECT contract._fld670::date AS activation_date,
           client._code::text AS client_code
    FROM public._reference59 AS contract
    JOIN public._reference141x1 AS client
      ON client._idrref = contract._fld681rref
    WHERE contract._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND contract._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
      AND contract._fld672 > $1::timestamp without time zone
      AND contract._fld693 >= 30
      AND contract._fld672 - contract._fld671 >= INTERVAL '30 days'
      AND contract._description::text NOT LIKE '%ИП%'
      AND contract._description::text NOT LIKE '%сотрудн%'
      AND client._code IS NOT NULL
      AND contract._fld670 IS NOT NULL
), purchase_days AS MATERIALIZED (
    SELECT g.client_id,
           g.guest_visit_date,
           min(c.activation_date) AS purchase_activation_date
    FROM guest_days AS g
    JOIN suitable_contracts AS c
      ON c.client_code = g.client_code
     AND c.activation_date >= g.guest_visit_date
     AND c.activation_date <= g.guest_visit_date + 44
    GROUP BY 1, 2
)
SELECT encode(g.client_id, 'hex') AS client_id,
       g.client_code,
       g.guest_visit_date,
       (a.client_id IS NOT NULL) AS accuniq_same_day_flag,
       p.purchase_activation_date,
       (p.purchase_activation_date - g.guest_visit_date)::smallint AS purchase_lag_days
FROM guest_days AS g
LEFT JOIN accuniq_days AS a
  ON a.client_id = g.client_id
 AND a.accuniq_date = g.guest_visit_date
LEFT JOIN purchase_days AS p
  ON p.client_id = g.client_id
 AND p.guest_visit_date = g.guest_visit_date;
