-- Independent source controls for mart.contract_usage.
-- $1: inclusive legacy-window start; $2: exclusive legacy-window end.
-- These statements intentionally reproduce the current Power Query grouping
-- by contract_code rather than invoking contract_usage_source_extract.sql.

-- CU-S01: physical one-row register key, source states and polymorphic
-- reference domain in the exact legacy output population.
WITH current_m_rows AS MATERIALIZED (
    SELECT a._recordertref, a._recorderrref, a._lineno,
           a._fld7578_type, a._fld7578_rtref, a._fld7578_rrref,
           a._active, d._posted, d._marked, c._code::text AS contract_code
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d ON d._idrref = a._recorderrref
    JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    JOIN public._reference141x1 AS client ON client._idrref = d._fld4171rref
    JOIN public._reference59 AS c ON c._idrref = a._fld7578_rrref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date AND a._period < $2::date
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
      AND c._code IS NOT NULL
), type_pairs AS (
    SELECT encode(_fld7578_type, 'hex') AS type_hex,
           encode(_fld7578_rtref, 'hex') AS rtref_hex
    FROM current_m_rows
    GROUP BY 1, 2
)
SELECT 'CU-S01'::text AS control_id,
       count(*)::bigint AS legacy_rows,
       (count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)))::bigint
           AS duplicate_technical_key_rows,
       count(DISTINCT _recorderrref)::bigint AS distinct_visit_documents,
       count(DISTINCT _fld7578_rrref)::bigint AS distinct_contract_ids,
       count(*) FILTER (WHERE NOT _active)::bigint AS inactive_movement_rows,
       count(*) FILTER (WHERE NOT _posted)::bigint AS unposted_document_rows,
       count(*) FILTER (WHERE _marked)::bigint AS marked_document_rows,
       (SELECT count(*)::bigint FROM type_pairs) AS polymorphic_type_pair_count,
       (SELECT string_agg(type_hex || '/' || rtref_hex, ',' ORDER BY type_hex, rtref_hex)
          FROM type_pairs) AS polymorphic_type_pairs
FROM current_m_rows;

-- CU-S02: current Power Query groups by code.  A physical one-contract row is
-- admissible only when no code aggregates multiple contract IDs.
WITH current_m_rows AS MATERIALIZED (
    SELECT c._code::text AS contract_code, c._idrref AS contract_id
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d ON d._idrref = a._recorderrref
    JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    JOIN public._reference141x1 AS client ON client._idrref = d._fld4171rref
    JOIN public._reference59 AS c ON c._idrref = a._fld7578_rrref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date AND a._period < $2::date
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
      AND c._code IS NOT NULL
), code_groups AS (
    SELECT contract_code, count(DISTINCT contract_id)::bigint AS contract_ids
    FROM current_m_rows GROUP BY contract_code
)
SELECT 'CU-S02'::text AS control_id,
       count(*)::bigint AS current_pbi_contract_code_groups,
       count(*) FILTER (WHERE contract_ids > 1)::bigint AS duplicate_code_groups,
       coalesce(sum(contract_ids) FILTER (WHERE contract_ids > 1), 0)::bigint
           AS contract_ids_in_duplicate_code_groups,
       coalesce(max(contract_ids), 0)::bigint AS max_contract_ids_per_code
FROM code_groups;

-- CU-S03: independent expected target-grain totals and target-contract input
-- quality.  The physical runner captures this before COPY in its own source
-- snapshot; physical delivery is rejected if any violation is nonzero.
WITH current_m_rows AS MATERIALIZED (
    SELECT c._idrref AS contract_id,
           c._code::text AS contract_code,
           c._fld671::date AS membership_start_date,
           c._fld672::date AS membership_end_date,
           c._fld693::numeric AS membership_term_days
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d ON d._idrref = a._recorderrref
    JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    JOIN public._reference141x1 AS client ON client._idrref = d._fld4171rref
    JOIN public._reference59 AS c ON c._idrref = a._fld7578_rrref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date AND a._period < $2::date
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
      AND c._code IS NOT NULL
), contract_groups AS (
    SELECT contract_id, contract_code, membership_start_date, membership_end_date,
           membership_term_days, count(*)::bigint AS visit_count
    FROM current_m_rows
    GROUP BY contract_id, contract_code, membership_start_date, membership_end_date,
             membership_term_days
)
SELECT 'CU-S03'::text AS control_id,
       count(*)::bigint AS target_grain_rows,
       coalesce(sum(visit_count), 0)::bigint AS visit_count_sum,
       min(membership_start_date) AS min_membership_start_date,
       max(membership_end_date) AS max_membership_end_date,
       count(*) FILTER (WHERE membership_start_date IS NULL OR membership_end_date IS NULL)
           ::bigint AS null_membership_date_rows,
       count(*) FILTER (WHERE membership_end_date < membership_start_date)::bigint
           AS reversed_membership_interval_rows,
       count(*) FILTER (WHERE membership_term_days IS NULL)::bigint AS null_term_rows,
       count(*) FILTER (WHERE membership_term_days < 0)::bigint AS negative_term_rows,
       count(*) FILTER (WHERE visit_count <= 0)::bigint AS nonpositive_visit_count_rows
FROM contract_groups;
