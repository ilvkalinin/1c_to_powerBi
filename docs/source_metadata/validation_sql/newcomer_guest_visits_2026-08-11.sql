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

ROLLBACK;
