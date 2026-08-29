-- RM-ASOF-S2-001 — source-side controls. Execute only in REPEATABLE READ, READ ONLY.
-- The cohort is intentionally the current mart's contract/client eligibility domain.

-- ASOF-V05: a period tie has no approved historical tie-breaker in the source mapping.
WITH cohort_clients AS (
    SELECT DISTINCT a._fld681rref AS client_id
    FROM public._reference59 AS a
    INNER JOIN public._reference141x1 AS c
        ON c._idrref = a._fld681rref
       AND c._code IS NOT NULL
    LEFT JOIN public._document332 AS d332
        ON d332._fld4422rref = a._idrref
       AND d332._posted
    LEFT JOIN public._document287 AS d287
        ON d287._fld3379rref = a._idrref
    WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND a._fld699rref NOT IN (
          decode('96976725cebf51f7461429d74d3f6cbe', 'hex'),
          decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
      )
      AND a._fld672 >= DATE '2024-01-02'
      AND a._fld672 < DATE '2027-02-01'
      AND a._fld693 >= 30
      AND a._description NOT LIKE '%ИП%'
      AND a._description NOT LIKE '%сотрудн%'
      AND extract(day FROM a._fld672 - a._fld671) >= 30
      AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00'
      AND d332._idrref IS NULL
      AND d287._idrref IS NULL
),
rating_period_ties AS (
    SELECT r._fld6862rref AS client_id, r._period
    FROM public._inforg6861 AS r
    INNER JOIN cohort_clients AS cc ON cc.client_id = r._fld6862rref
    GROUP BY r._fld6862rref, r._period
    HAVING count(*) > 1
),
tenure_period_ties AS (
    SELECT t._fld5655rref AS client_id, t._period
    FROM public._inforg5654 AS t
    INNER JOIN cohort_clients AS cc ON cc.client_id = t._fld5655rref
    GROUP BY t._fld5655rref, t._period
    HAVING count(*) > 1
)
SELECT
    'ASOF-V05'::text AS control_id,
    (SELECT count(*) FROM cohort_clients)::bigint AS cohort_clients,
    (SELECT count(*) FROM rating_period_ties)::bigint AS rating_period_tie_groups,
    (SELECT count(DISTINCT client_id) FROM rating_period_ties)::bigint AS rating_clients_with_ties,
    (SELECT count(*) FROM tenure_period_ties)::bigint AS tenure_period_tie_groups,
    (SELECT count(DISTINCT client_id) FROM tenure_period_ties)::bigint AS tenure_clients_with_ties;

-- ASOF-V05-META: field types are metadata evidence only, not a semantic history claim.
SELECT
    'ASOF-V05-META'::text AS control_id,
    string_agg(format('%s.%s:%s', table_name, column_name, data_type), ', ' ORDER BY table_name, column_name) AS period_field_types
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
      (table_name = '_inforg6861' AND column_name IN ('_fld6862rref', '_fld6863rref', '_period'))
      OR (table_name = '_inforg5654' AND column_name IN ('_fld5655rref', '_fld5656rref', '_period'))
  );

-- ASOF-V06: current interaction eligibility exposes created and started timestamps,
-- but does not by itself preserve task state/reason history.
WITH cohort_clients AS (
    SELECT DISTINCT a._fld681rref AS client_id
    FROM public._reference59 AS a
    INNER JOIN public._reference141x1 AS c
        ON c._idrref = a._fld681rref
       AND c._code IS NOT NULL
    LEFT JOIN public._document332 AS d332
        ON d332._fld4422rref = a._idrref
       AND d332._posted
    LEFT JOIN public._document287 AS d287
        ON d287._fld3379rref = a._idrref
    WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND a._fld699rref NOT IN (
          decode('96976725cebf51f7461429d74d3f6cbe', 'hex'),
          decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
      )
      AND a._fld672 >= DATE '2024-01-02'
      AND a._fld672 < DATE '2027-02-01'
      AND a._fld693 >= 30
      AND a._description NOT LIKE '%ИП%'
      AND a._description NOT LIKE '%сотрудн%'
      AND extract(day FROM a._fld672 - a._fld671) >= 30
      AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00'
      AND d332._idrref IS NULL
      AND d287._idrref IS NULL
),
eligible_interactions AS (
    SELECT i._fld820 AS started_at, i._fld823 AS created_at
    FROM public._reference67 AS i
    INNER JOIN public._reference106 AS task
        ON task._idrref = i._owneridrref
    INNER JOIN cohort_clients AS cc ON cc.client_id = task._fld1196rref
    INNER JOIN public._reference141x1 AS client
        ON client._idrref = task._fld1196rref
    INNER JOIN public._reference89 AS typ
        ON typ._idrref = task._fld1191rref
    LEFT JOIN public._reference202 AS src
        ON src._idrref = i._fld828rref
    LEFT JOIN public._reference224 AS state
        ON state._idrref = i._fld829rref
    WHERE i._fld823 >= DATE '2023-11-01'
      AND typ._description = 'Продажа клубной карты'
      AND i._fld831rref <> decode('8f6da46ad3a0c51b4bb9feb594cb3b9c', 'hex')
      AND state._description IS DISTINCT FROM 'Запланировано'
      AND src._description IS DISTINCT FROM 'Авто'
      AND client._code IS NOT NULL
      AND i._fld820 <> TIMESTAMP '0001-01-01 00:00:00'
)
SELECT
    'ASOF-V06'::text AS control_id,
    count(*)::bigint AS eligible_interactions,
    count(*) FILTER (WHERE created_at IS NULL)::bigint AS null_created_at,
    count(*) FILTER (WHERE started_at IS NULL)::bigint AS null_started_at,
    count(*) FILTER (WHERE created_at > started_at)::bigint AS created_after_started,
    count(*) FILTER (WHERE started_at > current_timestamp)::bigint AS future_started_at,
    min(created_at) AS min_created_at,
    max(created_at) AS max_created_at,
    min(started_at) AS min_started_at,
    max(started_at) AS max_started_at
FROM eligible_interactions;

-- ASOF-V06-META: confirms the timestamp columns exposed by the current extract.
SELECT
    'ASOF-V06-META'::text AS control_id,
    string_agg(format('%s.%s:%s', table_name, column_name, data_type), ', ' ORDER BY table_name, column_name) AS interaction_field_types
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
      (table_name = '_reference67' AND column_name IN ('_fld820', '_fld823', '_fld828rref', '_fld829rref', '_fld831rref', '_owneridrref'))
      OR (table_name = '_reference106' AND column_name IN ('_fld1191rref', '_fld1196rref', '_fld1201rref', '_fld1205rref'))
  );

-- ASOF-V07: current contract dates/activation can be measured, but record creation
-- and contract-state history require separately confirmed semantics and sources.
WITH cohort_contracts AS (
    SELECT a._fld670 AS activated_at, a._fld671 AS started_at, a._fld672 AS ended_at, a._fld674 AS purchased_at
    FROM public._reference59 AS a
    INNER JOIN public._reference141x1 AS c
        ON c._idrref = a._fld681rref
       AND c._code IS NOT NULL
    LEFT JOIN public._document332 AS d332
        ON d332._fld4422rref = a._idrref
       AND d332._posted
    LEFT JOIN public._document287 AS d287
        ON d287._fld3379rref = a._idrref
    WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND a._fld699rref NOT IN (
          decode('96976725cebf51f7461429d74d3f6cbe', 'hex'),
          decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
      )
      AND a._fld672 >= DATE '2024-01-02'
      AND a._fld672 < DATE '2027-02-01'
      AND a._fld693 >= 30
      AND a._description NOT LIKE '%ИП%'
      AND a._description NOT LIKE '%сотрудн%'
      AND extract(day FROM a._fld672 - a._fld671) >= 30
      AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00'
      AND d332._idrref IS NULL
      AND d287._idrref IS NULL
)
SELECT
    'ASOF-V07'::text AS control_id,
    count(*)::bigint AS cohort_contracts,
    count(*) FILTER (WHERE activated_at = TIMESTAMP '0001-01-01 00:00:00')::bigint AS activation_sentinel_rows,
    count(*) FILTER (WHERE activated_at <> TIMESTAMP '0001-01-01 00:00:00' AND activated_at > started_at)::bigint AS activation_after_start_rows,
    count(*) FILTER (WHERE purchased_at > started_at)::bigint AS purchased_after_start_rows,
    count(*) FILTER (WHERE ended_at <= started_at)::bigint AS invalid_service_interval_rows,
    min(activated_at) FILTER (WHERE activated_at <> TIMESTAMP '0001-01-01 00:00:00') AS min_activated_at,
    max(activated_at) FILTER (WHERE activated_at <> TIMESTAMP '0001-01-01 00:00:00') AS max_activated_at
FROM cohort_contracts;

-- ASOF-V07-META: the physical fields inspected above; metadata alone does not
-- establish which timestamp is a creation/audit timestamp or a history feed.
SELECT
    'ASOF-V07-META'::text AS control_id,
    string_agg(format('%s:%s', column_name, data_type), ', ' ORDER BY column_name) AS contract_field_types,
    string_agg(column_name, ', ' ORDER BY column_name) FILTER (WHERE data_type LIKE 'timestamp%') AS timestamp_columns_in_reference59
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = '_reference59'
  AND column_name IN ('_fld670', '_fld671', '_fld672', '_fld674', '_fld681rref');
