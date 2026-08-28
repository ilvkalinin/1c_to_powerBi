-- Independent source controls for mart.fitness_funnel_client_start.
-- $1: inclusive start-date boundary; $2: exclusive start-date boundary.
-- Execute each statement in its own fresh reader on the exported source
-- snapshot before target COPY.  The controls intentionally do not call the
-- source extract.

-- FF-S01: physical source shape, states and required lookup references.
WITH current_m_population AS MATERIALIZED (
    SELECT r._idrref AS contract_ref,
           r._fld681rref AS client_ref,
           r._fld687rref AS club_ref,
           r._marked AS contract_marked,
           client._idrref AS joined_client_ref,
           club._idrref AS joined_club_ref
    FROM public._reference59 AS r
    JOIN public._reference141x1 AS client
      ON client._idrref = r._fld681rref
    LEFT JOIN public._reference132 AS club
      ON club._idrref = r._fld687rref
    WHERE r._fld671 >= greatest($1::date, DATE '2024-01-01')
      AND r._fld671 < $2::date
      AND r._fld671 < r._fld672
      AND r._fld671 < CURRENT_DATE
      AND r._description::text NOT LIKE '%ИП%'
      AND r._description::text NOT LIKE '%сотруд%'
      AND client._code IS NOT NULL
      AND client._description IS NOT NULL
      AND r._fld681rref <> decode('00000000000000000000000000000000', 'hex')
      AND r._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND r._fld693 > 6
      AND r._fld694rref = ANY (ARRAY[
          decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex'),
          decode('9e369ac955bf602149e17b549b0f1498', 'hex'),
          decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex')
      ])
      AND r._fld670 IS NOT NULL
      AND client._fld1507 IS NOT NULL
      AND extract(epoch FROM (r._fld670 - client._fld1507)) / 86400.0 / 365.0 >= 14
)
SELECT 'FF-S01'::text AS control_id,
       count(*)::bigint AS eligible_contract_rows,
       (count(*) - count(DISTINCT contract_ref))::bigint AS duplicate_contract_ref_rows,
       count(*) FILTER (WHERE contract_marked)::bigint AS marked_contract_rows,
       count(*) FILTER (WHERE joined_client_ref IS NULL)::bigint AS client_orphan_rows,
       count(*) FILTER (WHERE club_ref IS NULL OR joined_club_ref IS NULL)::bigint AS club_orphan_rows
FROM current_m_population;

-- FF-S02: client-start cohort cardinality and display-attribute ambiguity.
WITH current_m_population AS MATERIALIZED (
    SELECT r._fld681rref AS client_ref,
           r._fld671::date AS membership_start_date,
           r._fld687rref AS club_ref,
           r._fld694rref AS tenure_ref
    FROM public._reference59 AS r
    JOIN public._reference141x1 AS client
      ON client._idrref = r._fld681rref
    WHERE r._fld671 >= greatest($1::date, DATE '2024-01-01')
      AND r._fld671 < $2::date
      AND r._fld671 < r._fld672
      AND r._fld671 < CURRENT_DATE
      AND r._description::text NOT LIKE '%ИП%'
      AND r._description::text NOT LIKE '%сотруд%'
      AND client._code IS NOT NULL
      AND client._description IS NOT NULL
      AND r._fld681rref <> decode('00000000000000000000000000000000', 'hex')
      AND r._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND r._fld693 > 6
      AND r._fld694rref = ANY (ARRAY[
          decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex'),
          decode('9e369ac955bf602149e17b549b0f1498', 'hex'),
          decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex')
      ])
      AND r._fld670 IS NOT NULL
      AND client._fld1507 IS NOT NULL
      AND extract(epoch FROM (r._fld670 - client._fld1507)) / 86400.0 / 365.0 >= 14
), cohort_groups AS (
    SELECT client_ref, membership_start_date,
           count(*)::bigint AS contract_rows,
           count(DISTINCT club_ref)::bigint AS club_values,
           count(DISTINCT tenure_ref)::bigint AS tenure_values
    FROM current_m_population
    GROUP BY client_ref, membership_start_date
)
SELECT 'FF-S02'::text AS control_id,
       (SELECT count(*)::bigint FROM current_m_population) AS eligible_contract_rows,
       count(*)::bigint AS cohort_rows,
       count(*) FILTER (WHERE contract_rows > 1)::bigint AS multi_contract_cohorts,
       coalesce(sum(contract_rows) FILTER (WHERE contract_rows > 1), 0)::bigint AS contracts_in_multi_cohorts,
       coalesce(max(contract_rows), 0)::bigint AS max_contracts_per_cohort,
       count(*) FILTER (WHERE club_values > 1)::bigint AS multi_club_cohorts,
       count(*) FILTER (WHERE tenure_values > 1)::bigint AS multi_tenure_cohorts
FROM cohort_groups;

-- FF-S03: independent expected target shape and date/null contract.
WITH current_m_population AS MATERIALIZED (
    SELECT r._fld681rref AS client_ref,
           r._fld671::date AS membership_start_date,
           r._fld687rref AS club_ref,
           CASE r._fld694rref
               WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex') THEN 'New'
               WHEN decode('9e369ac955bf602149e17b549b0f1498', 'hex') THEN 'Ex'
               WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex') THEN 'Renew'
           END::text AS tenure_type
    FROM public._reference59 AS r
    JOIN public._reference141x1 AS client
      ON client._idrref = r._fld681rref
    WHERE r._fld671 >= greatest($1::date, DATE '2024-01-01')
      AND r._fld671 < $2::date
      AND r._fld671 < r._fld672
      AND r._fld671 < CURRENT_DATE
      AND r._description::text NOT LIKE '%ИП%'
      AND r._description::text NOT LIKE '%сотруд%'
      AND client._code IS NOT NULL
      AND client._description IS NOT NULL
      AND r._fld681rref <> decode('00000000000000000000000000000000', 'hex')
      AND r._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND r._fld693 > 6
      AND r._fld694rref = ANY (ARRAY[
          decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex'),
          decode('9e369ac955bf602149e17b549b0f1498', 'hex'),
          decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex')
      ])
      AND r._fld670 IS NOT NULL
      AND client._fld1507 IS NOT NULL
      AND extract(epoch FROM (r._fld670 - client._fld1507)) / 86400.0 / 365.0 >= 14
), target_candidate AS (
    SELECT client_ref, membership_start_date, club_ref, tenure_type
    FROM current_m_population
    GROUP BY client_ref, membership_start_date, club_ref, tenure_type
)
SELECT 'FF-S03'::text AS control_id,
       count(*)::bigint AS target_candidate_rows,
       min(membership_start_date) AS min_membership_start_date,
       max(membership_start_date) AS max_membership_start_date,
       count(*) FILTER (WHERE client_ref IS NULL OR membership_start_date IS NULL
                         OR club_ref IS NULL OR tenure_type IS NULL)::bigint AS required_null_rows,
       count(*) FILTER (WHERE membership_start_date >= CURRENT_DATE)::bigint AS future_start_rows,
       (count(*) - count(DISTINCT (client_ref, membership_start_date)))::bigint AS duplicate_target_key_rows
FROM target_candidate;
