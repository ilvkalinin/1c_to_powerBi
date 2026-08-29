-- RM-S2-01—RM-S2-07: full-population, source-only validation for
-- mart.renewal_management_contract.  Each statement returns no operational IDs.
-- Execute each statement in a fresh REPEATABLE READ, READ ONLY transaction.

-- RM-S2-01: exact legacy cohort is one current source contract after both
-- exclusion branches.  Current Power Query intentionally has no D287 state
-- predicate; document states are observed, not silently filtered.
WITH candidate AS MATERIALIZED (
    SELECT a._idrref AS contract_id
    FROM public._reference59 AS a
    JOIN public._reference141x1 AS cl ON cl._idrref = a._fld681rref
    WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe', 'hex'), decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex'))
      AND a._fld672 > DATE '2024-01-01'
      AND a._fld672 <= date_trunc('month', current_date) + interval '6 month' - interval '1 day'
      AND a._fld693 >= 30
      AND a._description NOT LIKE '%ИП%'
      AND a._description NOT LIKE '%сотрудн%'
      AND extract(day FROM (a._fld672 - a._fld671)) >= 30
      AND cl._code IS NOT NULL
      AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00'
), cohort AS MATERIALIZED (
    SELECT c.contract_id
    FROM candidate AS c
    LEFT JOIN public._document332 AS d332
      ON d332._fld4422rref = c.contract_id AND d332._posted = true
    LEFT JOIN public._document287 AS d287 ON d287._fld3379rref = c.contract_id
    WHERE d332._idrref IS NULL AND d287._idrref IS NULL
)
SELECT 'RM-S2-01'::text AS control_id,
       (SELECT count(*)::bigint FROM candidate) AS pre_exclusion_contract_rows,
       count(*)::bigint AS cohort_rows,
       count(DISTINCT contract_id)::bigint AS distinct_contract_ids,
       (count(*) - count(DISTINCT contract_id))::bigint AS duplicate_contract_rows,
       (SELECT count(*)::bigint FROM public._document332 AS d JOIN candidate AS c ON c.contract_id = d._fld4422rref) AS document332_rows,
       (SELECT count(*) FILTER (WHERE d._posted)::bigint FROM public._document332 AS d JOIN candidate AS c ON c.contract_id = d._fld4422rref) AS document332_posted_rows,
       (SELECT count(*)::bigint FROM public._document287 AS d JOIN candidate AS c ON c.contract_id = d._fld3379rref) AS document287_rows,
       (SELECT count(*) FILTER (WHERE d._posted)::bigint FROM public._document287 AS d JOIN candidate AS c ON c.contract_id = d._fld3379rref) AS document287_posted_rows,
       (SELECT count(*) FILTER (WHERE d._marked)::bigint FROM public._document287 AS d JOIN candidate AS c ON c.contract_id = d._fld3379rref) AS document287_marked_rows
FROM cohort;

-- RM-S2-02: current old-to-next same-client/first-start rule has no hidden
-- minimum-start tie.  A nonzero tie is an implementation blocker: current
-- SQL has ORDER BY start only and no permitted deterministic replacement.
WITH cohort AS MATERIALIZED (
    SELECT a._idrref AS contract_id, a._fld681rref AS client_id,
           a._fld671 AS start_at, a._fld672 AS end_at
    FROM public._reference59 AS a
    JOIN public._reference141x1 AS cl ON cl._idrref = a._fld681rref
    LEFT JOIN public._document332 AS d332 ON d332._fld4422rref = a._idrref AND d332._posted = true
    LEFT JOIN public._document287 AS d287 ON d287._fld3379rref = a._idrref
    WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe', 'hex'), decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex'))
      AND a._fld672 > DATE '2024-01-01'
      AND a._fld672 <= date_trunc('month', current_date) + interval '6 month' - interval '1 day'
      AND a._fld693 >= 30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
      AND extract(day FROM (a._fld672 - a._fld671)) >= 30 AND cl._code IS NOT NULL
      AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00' AND d332._idrref IS NULL AND d287._idrref IS NULL
), selected AS MATERIALIZED (
    SELECT c.contract_id, first_candidate.next_start, first_candidate.next_marked,
           coalesce(tie_count.n, 0)::bigint AS earliest_start_candidates
    FROM cohort AS c
    LEFT JOIN LATERAL (
        SELECT n._fld671 AS next_start, n._marked AS next_marked
        FROM public._reference59 AS n
        WHERE n._fld681rref = c.client_id
          AND n._fld671 > c.start_at AND n._fld672 > c.end_at AND n._fld672 > n._fld671
          AND n._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
          AND n._fld699rref <> decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
          AND ((n._fld693 >= 30 AND n._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex'))
            OR (n._fld693 >= 1 AND n._fld699rref = decode('96976725cebf51f7461429d74d3f6cbe', 'hex')))
          AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
        ORDER BY n._fld671
        LIMIT 1
    ) AS first_candidate ON TRUE
    LEFT JOIN LATERAL (
        SELECT count(*)::bigint AS n
        FROM public._reference59 AS n
        WHERE first_candidate.next_start IS NOT NULL
          AND n._fld681rref = c.client_id AND n._fld671 = first_candidate.next_start
          AND n._fld671 > c.start_at AND n._fld672 > c.end_at AND n._fld672 > n._fld671
          AND n._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
          AND n._fld699rref <> decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
          AND ((n._fld693 >= 30 AND n._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex'))
            OR (n._fld693 >= 1 AND n._fld699rref = decode('96976725cebf51f7461429d74d3f6cbe', 'hex')))
          AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
    ) AS tie_count ON TRUE
)
SELECT 'RM-S2-02'::text AS control_id,
       (SELECT count(*)::bigint FROM cohort) AS cohort_rows,
       coalesce(sum(earliest_start_candidates), 0)::bigint AS earliest_start_candidate_rows,
       count(*) FILTER (WHERE next_start IS NOT NULL)::bigint AS cohorts_with_next_contract,
       count(*) FILTER (WHERE earliest_start_candidates > 1)::bigint AS earliest_start_tie_groups,
       coalesce(sum(earliest_start_candidates) FILTER (WHERE earliest_start_candidates > 1), 0)::bigint AS candidates_in_ties,
       coalesce(max(earliest_start_candidates), 0)::bigint AS max_earliest_start_multiplicity,
       count(*) FILTER (WHERE next_start IS NOT NULL AND next_marked)::bigint AS selected_next_marked_rows
FROM selected;

-- RM-S2-03: contract ID is the target key.  Code is retained as a display and
-- current-PBI join value, so duplicate cohort codes are an explicit risk.
WITH cohort AS MATERIALIZED (
    SELECT a._idrref AS contract_id, a._code::text AS contract_code
    FROM public._reference59 AS a
    JOIN public._reference141x1 AS cl ON cl._idrref = a._fld681rref
    LEFT JOIN public._document332 AS d332 ON d332._fld4422rref = a._idrref AND d332._posted = true
    LEFT JOIN public._document287 AS d287 ON d287._fld3379rref = a._idrref
    WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe', 'hex'), decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex'))
      AND a._fld672 > DATE '2024-01-01'
      AND a._fld672 <= date_trunc('month', current_date) + interval '6 month' - interval '1 day'
      AND a._fld693 >= 30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
      AND extract(day FROM (a._fld672 - a._fld671)) >= 30 AND cl._code IS NOT NULL
      AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00' AND d332._idrref IS NULL AND d287._idrref IS NULL
), code_groups AS (
    SELECT contract_code, count(DISTINCT contract_id)::bigint AS contract_ids
    FROM cohort GROUP BY contract_code
)
SELECT 'RM-S2-03'::text AS control_id,
       (SELECT count(*)::bigint FROM cohort) AS cohort_rows,
       count(*)::bigint AS distinct_nonnull_code_rows,
       count(*) FILTER (WHERE contract_ids > 1)::bigint AS duplicate_code_groups,
       coalesce(sum(contract_ids) FILTER (WHERE contract_ids > 1), 0)::bigint AS contracts_in_duplicate_code_groups,
       coalesce(max(contract_ids), 0)::bigint AS max_contracts_per_code
FROM code_groups;

-- RM-S2-08: physical types needed by the documented SQL contract.  This is
-- metadata only; it never makes a business semantic claim from a technical name.
SELECT 'RM-S2-08'::text AS control_id,
       count(*)::bigint AS required_columns_found,
       count(*) FILTER (WHERE data_type IS NULL)::bigint AS missing_columns,
       string_agg(table_name || '.' || column_name || ':' || data_type, ', ' ORDER BY table_name, column_name) AS physical_types
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (table_name, column_name) IN (
    ('_reference59','_idrref'), ('_reference59','_code'), ('_reference59','_fld670'),
    ('_reference59','_fld671'), ('_reference59','_fld672'), ('_reference59','_fld693'),
    ('_reference59','_fld681rref'), ('_reference59','_fld687rref'), ('_reference59','_marked'),
    ('_reference141x1','_fld1507'), ('_reference141x1','_fld1531'),
    ('_accumrg7739','_fld7749'), ('_accumrg7575','_fld7585'),
    ('_inforg6861','_period'), ('_inforg5654','_period'), ('_reference67','_fld820')
  );

-- RM-S2-04: latest rating and tenure joins must remain one row per client.
WITH rating_period AS (
    SELECT _fld6862rref AS client_id, max(_period) AS period
    FROM public._inforg6861 WHERE _fld6862rref IS NOT NULL GROUP BY _fld6862rref
), rating_ties AS (
    SELECT r._fld6862rref AS client_id, count(*)::bigint AS n
    FROM public._inforg6861 AS r JOIN rating_period AS m ON m.client_id = r._fld6862rref AND m.period = r._period
    JOIN public._reference141x1 AS c ON c._idrref = r._fld6862rref AND c._code IS NOT NULL
    GROUP BY r._fld6862rref HAVING count(*) > 1
), tenure_period AS (
    SELECT _fld5655rref AS client_id, max(_period) AS period
    FROM public._inforg5654 WHERE _fld5655rref IS NOT NULL GROUP BY _fld5655rref
), tenure_ties AS (
    SELECT t._fld5655rref AS client_id, count(*)::bigint AS n
    FROM public._inforg5654 AS t JOIN tenure_period AS m ON m.client_id = t._fld5655rref AND m.period = t._period
    JOIN public._reference141x1 AS c ON c._idrref = t._fld5655rref AND c._code IS NOT NULL
    GROUP BY t._fld5655rref HAVING count(*) > 1
)
SELECT 'RM-S2-04'::text AS control_id,
       (SELECT count(*)::bigint FROM rating_ties) AS rating_latest_tie_groups,
       (SELECT coalesce(max(n), 0)::bigint FROM rating_ties) AS rating_max_multiplicity,
       (SELECT count(*)::bigint FROM tenure_ties) AS tenure_latest_tie_groups,
       (SELECT coalesce(max(n), 0)::bigint FROM tenure_ties) AS tenure_max_multiplicity;

-- RM-S2-05: the current interaction ROW_NUMBER has a date-only ordering;
-- equal latest timestamps per client would make its selected attributes unstable.
WITH eligible AS MATERIALIZED (
    SELECT client._idrref AS client_id, i._fld820 AS interaction_at
    FROM public._reference67 AS i
    JOIN public._reference106 AS task ON task._idrref = i._owneridrref
    JOIN public._reference141x1 AS client ON client._idrref = task._fld1196rref
    JOIN public._reference89 AS task_type ON task_type._idrref = task._fld1191rref
    LEFT JOIN public._reference202 AS source_type ON source_type._idrref = i._fld828rref
    LEFT JOIN public._reference224 AS task_state ON task_state._idrref = i._fld829rref
    WHERE i._fld823 >= DATE '2023-11-01'
      AND task_type._description = 'Продажа клубной карты'
      AND i._fld831rref <> decode('8f6da46ad3a0c51b4bb9feb594cb3b9c', 'hex')
      AND task_state._description IS DISTINCT FROM 'Запланировано'
      AND source_type._description IS DISTINCT FROM 'Авто'
      AND client._code IS NOT NULL
      AND i._fld820 <> TIMESTAMP '0001-01-01 00:00:00'
), latest AS (
    SELECT client_id, max(interaction_at) AS interaction_at FROM eligible GROUP BY client_id
), ties AS (
    SELECT e.client_id, count(*)::bigint AS n
    FROM eligible AS e JOIN latest AS l USING (client_id, interaction_at)
    GROUP BY e.client_id HAVING count(*) > 1
)
SELECT 'RM-S2-05'::text AS control_id,
       (SELECT count(*)::bigint FROM eligible) AS eligible_interaction_rows,
       (SELECT count(*)::bigint FROM latest) AS clients_with_interaction,
       count(*)::bigint AS latest_interaction_tie_groups,
       coalesce(sum(n), 0)::bigint AS rows_in_latest_interaction_ties,
       coalesce(max(n), 0)::bigint AS max_latest_interaction_multiplicity
FROM ties;

-- RM-S2-06: current price path is RecordKind=0 only.  Key, state and orphan
-- observations prove whether its contract aggregation can be loaded once.
SELECT 'RM-S2-06'::text AS control_id,
       count(*)::bigint AS price_rows,
       count(DISTINCT (p._recordertref, p._recorderrref, p._lineno))::bigint AS technical_keys,
       (count(*) - count(DISTINCT (p._recordertref, p._recorderrref, p._lineno)))::bigint AS duplicate_technical_key_rows,
       count(*) FILTER (WHERE NOT p._active)::bigint AS inactive_price_rows,
       count(*) FILTER (WHERE c._idrref IS NULL)::bigint AS contract_orphan_rows,
       count(DISTINCT p._fld7741rref)::bigint AS contracts_with_price,
       coalesce(sum(p._fld7749), 0)::numeric AS price_sum
FROM public._accumrg7739 AS p
LEFT JOIN public._reference59 AS c ON c._idrref = p._fld7741rref
WHERE p._period > DATE '2015-01-01' AND p._recordkind = 0;

-- RM-S2-07: exact current-PBI 2026 visit path.  A target keyed by contract ID
-- is admissible only when code grouping does not merge IDs or duplicate rows.
WITH contracts AS MATERIALIZED (
    SELECT _code::text AS contract_code
    FROM public._reference59
    WHERE _fld672 > DATE '2024-01-01'
      AND _fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
), visits AS MATERIALIZED (
    SELECT r._idrref AS contract_id, r._code::text AS contract_code,
           a._recordertref, a._recorderrref, a._lineno
    FROM public._accumrg7575 AS a
    LEFT JOIN public._reference59 AS r ON r._idrref = a._fld7578_rrref
    JOIN contracts AS c ON c.contract_code = r._code::text
    LEFT JOIN public._document325 AS d ON d._idrref = a._recorderrref
    LEFT JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    LEFT JOIN public._reference141x1 AS client ON client._idrref = d._fld4171rref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01'
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
), code_groups AS (
    SELECT contract_code, count(DISTINCT contract_id)::bigint AS contract_ids
    FROM visits GROUP BY contract_code
)
SELECT 'RM-S2-07'::text AS control_id,
       (SELECT count(*)::bigint FROM visits) AS legacy_visit_rows,
       (SELECT count(DISTINCT (_recordertref, _recorderrref, _lineno))::bigint FROM visits) AS technical_keys,
       (SELECT count(DISTINCT contract_id)::bigint FROM visits) AS contract_ids,
       count(*) FILTER (WHERE contract_ids > 1)::bigint AS duplicate_code_groups,
       coalesce(sum(contract_ids) FILTER (WHERE contract_ids > 1), 0)::bigint AS contracts_in_duplicate_code_groups,
       coalesce(max(contract_ids), 0)::bigint AS max_contracts_per_code
FROM code_groups;
