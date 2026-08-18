-- SV-087: «Новички и гостевые визиты» — read-only source validation.
-- Execute only against gymdb with gymdb_readonly. No query returns PII or raw IDs.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000';

-- NV-V01 expected: all relations used by the three current report paths exist
-- in public. This confirms availability only; types, states and cardinalities
-- remain separate controls.
SELECT count(*) AS existing_relations
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('_accumrg7575', '_document325', '_reference59',
                    '_inforg7064', '_inforg5654', '_reference141x1',
                    '_reference132', '_reference163', '_reference67',
                    '_reference106', '_inforg7146', '_reference89',
                    '_reference224', '_reference225', '_inforg7006',
                    '_document329', '_enum448');

-- NV-V03 expected: the guest registry technical key is unique; every row has
-- a period, client and visit date. Status coverage is observed, never used to
-- introduce a new first-release filter.
SELECT count(*) AS rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS technical_keys,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS duplicate_technical_keys,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE _period IS NULL) AS null_period_rows,
       count(*) FILTER (WHERE _fld7065rref IS NULL) AS null_client_rows,
       count(*) FILTER (WHERE _fld7068 IS NULL) AS null_visit_date_rows,
       count(*) FILTER (WHERE _fld7067rref IS NULL) AS null_status_rows,
       count(DISTINCT _fld7067rref) AS distinct_non_null_statuses,
       count(*) FILTER (WHERE _fld7068::date < DATE '2000-01-01') AS pre_2000_visit_dates,
       count(*) FILTER (WHERE _fld7068::date > CURRENT_DATE) AS future_visit_dates,
       min(_fld7068)::date AS min_visit_date,
       max(_fld7068)::date AS max_visit_date
FROM public._inforg7064
WHERE _period >= DATE '2025-01-01' AND _period < DATE '2027-01-01';

-- NV-V04 expected: duplicate candidate keys are explicitly measured. A
-- nonzero result needs a documented current-rule choice; no DISTINCT is added
-- merely to force a desired count.
WITH duplicate_candidates AS (
  SELECT _fld7066rref AS guest_registration_id,
         _fld7065rref AS client_id,
         _fld7068::date AS guest_visit_date,
         count(*) AS rows_in_group
  FROM public._inforg7064
  WHERE _period >= DATE '2025-01-01' AND _period < DATE '2027-01-01'
  GROUP BY 1, 2, 3
  HAVING count(*) > 1
)
SELECT count(*) AS duplicate_candidate_groups,
       coalesce(sum(rows_in_group), 0) AS rows_in_duplicate_candidate_groups,
       coalesce(max(rows_in_group), 0) AS max_rows_per_candidate_key
FROM duplicate_candidates;

-- NV-V07 expected: as-of tenure history has no exact client-period ties. This
-- is a physical precondition only; the current M fallback to New remains a
-- separately unconfirmed business rule.
WITH history AS (
  SELECT _fld5655rref AS client_id, _period
  FROM public._inforg5654
), ties AS (
  SELECT client_id, _period, count(*) AS rows_in_tie
  FROM history GROUP BY 1, 2 HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM history) AS history_rows,
       (SELECT count(*) FROM ties) AS client_period_ties,
       coalesce((SELECT max(rows_in_tie) FROM ties), 0) AS max_rows_per_tie;

-- NV-V08 expected: the exact current-M tour filter is measured at interaction
-- grain before any future source-side aggregation. Phone-row multiplicity is
-- observed, never silently deduplicated; the current tour date remains the
-- phone date when present and interaction start otherwise.
WITH tours AS (
  SELECT i._idrref AS interaction_id,
         CASE
           WHEN s._description = 'Закрыто'
            AND i._fld830rref = decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex')
             THEN 'completed'
           WHEN s._description = 'Запланировано'
            AND i._fld830rref = decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex')
             THEN 'planned'
         END AS tour_kind
  FROM public._reference67 i
  JOIN public._reference106 task ON task._idrref = i._owneridrref
  JOIN public._reference224 s ON s._idrref = i._fld829rref
  LEFT JOIN public._inforg7146 phone ON phone._fld7151rref = i._idrref
  WHERE i._fld831rref = decode('b538e5326d9fc9a943c11fd0e7a0e678', 'hex')
    AND task._fld1191rref = decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex')
    AND coalesce(phone._fld7150, i._fld820) >= DATE '2025-01-01'
    AND coalesce(phone._fld7150, i._fld820) < CURRENT_DATE
    AND ((s._description = 'Закрыто'
          AND i._fld830rref = decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex'))
      OR (s._description = 'Запланировано'
          AND i._fld830rref = decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex')))
)
SELECT tour_kind,
       count(*) AS current_m_tour_rows,
       count(DISTINCT interaction_id) AS distinct_interactions,
       count(*) - count(DISTINCT interaction_id) AS phone_join_excess
FROM tours
GROUP BY 1 ORDER BY 1;

-- NV-V05. User-approved PBIT 2026-08-18 supplies the exact ACCUNIQ list and
-- sign rule. Expected: all 12 codes match Reference163; the result records
-- `_active` coverage and the PBIT groups with signed total 1 or 2. It
-- observes rather than introduces additional source filters.
WITH accuniq_codes(service_code) AS (
  VALUES ('00000017896'), ('00000018151'), ('00000017882'),
         ('00000017883'), ('00000018152'), ('00000017897'),
         ('00000016715'), ('00000016162'), ('00000016194'),
         ('00000016161'), ('00000017672'), ('00000016160')
), service_matches AS (
  SELECT c.service_code, count(s._idrref) AS physical_matches
  FROM accuniq_codes c
  LEFT JOIN public._reference163 s ON s._code::text = c.service_code
  GROUP BY 1
), movements AS (
  SELECT a._period::date AS movement_date,
         a._fld7577rref AS club_id,
         a._fld7576rref AS client_id,
         s._code::text AS service_code,
         CASE WHEN a._fld7585 = -1 THEN -1 ELSE 1 END AS pbit_signed_quantity,
         a._active
  FROM public._accumrg7575 a
  JOIN public._reference163 s ON s._idrref = a._fld7579rref
  JOIN accuniq_codes c ON c.service_code = s._code::text
  WHERE a._period >= DATE '2025-01-01'
), pbit_groups AS (
  SELECT movement_date, club_id, client_id, service_code,
         sum(pbit_signed_quantity) AS signed_total,
         count(*) AS movement_rows
  FROM movements
  GROUP BY 1, 2, 3, 4
)
SELECT (SELECT count(*) FROM service_matches WHERE physical_matches = 1)
           AS codes_with_one_physical_match,
       (SELECT count(*) FROM service_matches WHERE physical_matches <> 1)
           AS codes_without_one_physical_match,
       (SELECT count(*) FROM movements) AS scoped_movement_rows,
       (SELECT count(*) FROM movements WHERE NOT _active) AS inactive_movement_rows,
       (SELECT count(*) FROM pbit_groups WHERE signed_total IN (1, 2))
           AS current_pbit_qualified_groups,
       (SELECT count(*) FROM pbit_groups WHERE signed_total NOT IN (1, 2))
           AS excluded_by_current_pbit_quantity,
       (SELECT max(movement_rows) FROM pbit_groups) AS max_rows_per_pbit_group;

-- NV-V09. Expected: reproduce the current PBIT `ЗаписиНаАккуники` path:
-- select MAX(Period) per prebooking document (not per client), retain every
-- tie at that timestamp, then exclude enum orders 2 and 3. The control only
-- measures whether this legacy ordering can lose a client/date match; it does
-- not replace the prebooking key with a client key or introduce a tie-break.
WITH accuniq_codes(code) AS (
  VALUES ('00000017896'), ('00000018151'), ('00000017882'), ('00000017883'),
         ('00000018152'), ('00000017897'), ('00000016715'), ('00000016162'),
         ('00000016194'), ('00000016161'), ('00000017672'), ('00000016160')
),
base AS MATERIALIZED (
  SELECT r._period AS state_period,
         r._fld7007_rrref AS prebooking_id,
         r._fld7008rref AS client_id,
         e._enumorder AS state_order,
         d._fld4306::date AS scheduled_date
  FROM public._inforg7006 r
  JOIN public._document329 d ON d._idrref = r._fld7007_rrref
  JOIN public._reference141x1 client ON client._idrref = r._fld7008rref
  JOIN public._enum448 e ON e._idrref = r._fld7013rref
  JOIN public._reference163 service ON service._idrref = r._fld7010rref
  JOIN accuniq_codes c ON c.code = service._code::text
  WHERE r._period >= TIMESTAMP '2025-01-01'
),
latest_period AS MATERIALIZED (
  SELECT prebooking_id, max(state_period) AS state_period
  FROM base
  GROUP BY prebooking_id
),
latest_rows AS MATERIALIZED (
  SELECT b.*
  FROM base b
  JOIN latest_period lp
    ON lp.prebooking_id = b.prebooking_id
   AND lp.state_period = b.state_period
),
current_pbit_rows AS (
  SELECT * FROM latest_rows
  WHERE state_order NOT IN (2, 3)
),
client_date AS (
  SELECT client_id, scheduled_date, count(*) AS pbit_rows
  FROM current_pbit_rows
  GROUP BY 1, 2
)
SELECT (SELECT count(*) FROM base) AS source_rows,
       (SELECT count(DISTINCT prebooking_id) FROM base) AS prebookings,
       (SELECT count(*) FROM latest_rows) AS latest_rows,
       (SELECT count(*) FROM latest_rows) -
         (SELECT count(DISTINCT prebooking_id) FROM latest_rows) AS latest_tie_excess,
       (SELECT count(*) FILTER (WHERE state_order IN (2, 3)) FROM latest_rows)
         AS latest_rows_excluded_by_state,
       (SELECT count(*) FROM current_pbit_rows) AS current_pbit_rows,
       (SELECT count(*) FROM client_date) AS current_client_date_keys,
       (SELECT count(*) FROM current_pbit_rows) -
         (SELECT count(*) FROM client_date) AS client_date_duplicate_excess;

-- NV-V06. Expected: reproduce the current PBIT suitable-contract predicate
-- and the inclusive [0, 44] activation window after a guest visit. Lag 45 is
-- measured separately and must not be admitted by this control. The first
-- candidate remains MIN(lag_days) per client × guest date, as in current M;
-- no contract ID tie-break is introduced.
WITH guest_days AS MATERIALIZED (
  SELECT DISTINCT g._fld7065rref AS client_id,
         g._fld7068::date AS guest_date
  FROM public._inforg7064 g
  JOIN public._document325 d ON d._idrref = g._recorderrref
  JOIN public._reference141x1 client ON client._idrref = g._fld7065rref
  WHERE g._period > TIMESTAMP '2025-01-01'
    AND g._fld7068 IS NOT NULL
),
suitable_contracts AS MATERIALIZED (
  SELECT c._idrref AS contract_id,
         c._fld681rref AS client_id,
         c._fld670::date AS activation_date
  FROM public._reference59 c
  JOIN public._reference141x1 client ON client._idrref = c._fld681rref
  WHERE c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._fld672 > TIMESTAMP '2025-01-01'
    AND c._fld693 >= 30
    AND c._fld672 - c._fld671 >= INTERVAL '30 days'
    AND c._description::text NOT LIKE '%ИП%'
    AND c._description::text NOT LIKE '%сотрудн%'
    AND client._code IS NOT NULL
    AND c._fld670 IS NOT NULL
),
candidate_lags AS MATERIALIZED (
  SELECT gd.client_id, gd.guest_date, sc.contract_id,
         (sc.activation_date - gd.guest_date) AS lag_days
  FROM guest_days gd
  JOIN suitable_contracts sc ON sc.client_id = gd.client_id
  WHERE sc.activation_date >= gd.guest_date
    AND sc.activation_date <= gd.guest_date + 45
),
current_pbit_candidates AS (
  SELECT client_id, guest_date, min(lag_days) AS first_lag_days
  FROM candidate_lags
  WHERE lag_days BETWEEN 0 AND 44
  GROUP BY 1, 2
)
SELECT (SELECT count(*) FROM guest_days) AS guest_client_date_keys,
       (SELECT count(*) FROM candidate_lags WHERE lag_days = 0) AS lag_0_contract_rows,
       (SELECT count(*) FROM candidate_lags WHERE lag_days = 44) AS lag_44_contract_rows,
       (SELECT count(*) FROM candidate_lags WHERE lag_days = 45) AS lag_45_contract_rows,
       (SELECT count(*) FROM current_pbit_candidates) AS current_pbit_converted_guest_days,
       (SELECT count(*) FILTER (WHERE first_lag_days = 0)
        FROM current_pbit_candidates) AS converted_at_lag_0,
       (SELECT count(*) FILTER (WHERE first_lag_days = 44)
        FROM current_pbit_candidates) AS converted_at_lag_44;

-- NV-V02, closed control month 2026-07. Expected: exact current PBIT
-- first-visit candidate preserves one earliest movement per contract, unless
-- several movements have the same earliest timestamp. Such ties are observed,
-- never given an invented order. The full 2025+ window exceeded the safe
-- source timeout and is not presented as a result.
WITH candidates AS MATERIALIZED (
  SELECT a._period, a._fld7578_rrref AS contract_id,
         a._recorderrref AS visit_document_id,
         row_number() OVER (
           PARTITION BY a._fld7578_rrref ORDER BY a._period
         ) AS rn,
         min(a._period) OVER (PARTITION BY a._fld7578_rrref) AS first_period
  FROM public._accumrg7575 a
  JOIN public._document325 d ON d._idrref = a._recorderrref
  JOIN public._reference59 contract ON contract._idrref = a._fld7578_rrref
  WHERE a._period >= TIMESTAMP '2026-07-01'
    AND a._period < TIMESTAMP '2026-08-01'
    AND contract._fld694rref = decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex')
    AND d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
),
first_ties AS (
  SELECT contract_id, count(*) AS rows_at_first_period
  FROM candidates
  WHERE _period = first_period
  GROUP BY 1
  HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM candidates) AS candidate_movement_rows,
       (SELECT count(DISTINCT contract_id) FROM candidates) AS contracts,
       (SELECT count(*) FROM candidates WHERE rn = 1) AS current_pbit_first_rows,
       (SELECT count(*) FROM first_ties) AS contracts_with_first_period_tie,
       COALESCE((SELECT sum(rows_at_first_period) FROM first_ties), 0)
         AS rows_in_first_period_ties,
       COALESCE((SELECT max(rows_at_first_period) FROM first_ties), 0)
         AS max_rows_in_first_period_tie;

ROLLBACK;
