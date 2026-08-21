-- CRM technical SQL review, executed 2026-08-21 on VM-1 only.
-- Run in a READ ONLY transaction. No raw IDs, names, phones or comment text
-- are returned. The fixed month is a bounded cardinality/type control, not a
-- refresh horizon.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '30s';

-- CRM-TV01: relevant source representations. Expected: CRM reference IDs are
-- bytea; dates are timestamp without time zone; client phone is nullable.
SELECT c.relname AS relation_name,
       a.attname AS column_name,
       format_type(a.atttypid, a.atttypmod) AS data_type,
       a.attnotnull
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid
WHERE n.nspname = 'public'
  AND c.relname IN ('_reference67', '_reference106', '_inforg7146',
                    '_inforg6291', '_reference137', '_reference141x1',
                    '_inforg5810', '_reference110', '_reference145')
  AND a.attname IN ('_idrref', '_owneridrref', '_fld820', '_fld821',
                    '_fld822', '_fld823', '_fld824rref', '_fld828rref',
                    '_fld829rref', '_fld830rref', '_fld831rref',
                    '_fld1190rref', '_fld1191rref', '_fld1194rref',
                    '_fld1195rref', '_fld1196rref', '_fld1197rref',
                    '_fld1199rref', '_fld1202rref', '_fld1204rref',
                    '_fld8642rref', '_fld8643rref', '_fld7147rref',
                    '_fld7148', '_fld7150', '_fld7151rref', '_fld6292rref',
                    '_fld6296rref', '_fld6298', '_fld6299', '_fld1462rref',
                    '_fld1463', '_fld1464', '_fld1507', '_fld1527rref',
                    '_code', '_description', '_fld1200', '_fld5811_rrref',
                    '_fld5813_rrref')
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY 1, 2;

-- CRM-TV02: core-key, task join and source sentinel profile for July 2026.
WITH core AS MATERIALIZED (
  SELECT i._idrref AS interaction_id,
         i._owneridrref AS task_id,
         i._fld820 AS started_at,
         i._fld821 AS ended_at,
         i._fld822 AS planned_at,
         i._fld823 AS created_at,
         i._marked,
         i._fld9074 AS archived
  FROM public._reference67 i
  WHERE i._fld823 >= TIMESTAMP '2026-07-01'
    AND i._fld823 < TIMESTAMP '2026-08-01'
), task_join AS (
  SELECT c.interaction_id, t._idrref AS matched_task_id
  FROM core c
  LEFT JOIN public._reference106 t ON t._idrref = c.task_id
)
SELECT (SELECT count(*) FROM core) AS core_rows,
       (SELECT count(DISTINCT interaction_id) FROM core) AS distinct_core_ids,
       (SELECT count(*) FILTER (WHERE matched_task_id IS NULL) FROM task_join)
         AS missing_task_rows,
       (SELECT count(*) FILTER (WHERE started_at = TIMESTAMP '0001-01-01')
        FROM core) AS started_sentinel_rows,
       (SELECT count(*) FILTER (WHERE ended_at = TIMESTAMP '0001-01-01')
        FROM core) AS ended_sentinel_rows,
       (SELECT count(*) FILTER (WHERE planned_at = TIMESTAMP '0001-01-01')
        FROM core) AS planned_sentinel_rows,
       (SELECT count(*) FILTER (WHERE _marked) FROM core) AS marked_rows,
       (SELECT count(*) FILTER (WHERE archived) FROM core) AS archived_rows;

-- CRM-TV03: candidate physical keys for the factual children. The sales
-- sample preserves direct phone rows; feedback exposes comment multiplicity.
WITH phone_sample AS MATERIALIZED (
  SELECT i._idrref AS interaction_id,
         p._fld7147rref AS phone_reference_id,
         p._fld8699 AS phone_event_id
  FROM public._reference67 i
  JOIN public._reference106 t ON t._idrref = i._owneridrref
  JOIN public._inforg7146 p ON p._fld7151rref = i._idrref
  WHERE i._fld823 >= TIMESTAMP '2026-01-01'
    AND i._fld823 < TIMESTAMP '2027-01-01'
    AND t._fld1191rref IN (
      decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
      decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
      decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
    )
  ORDER BY p._fld7150, i._idrref, p._fld8699
  LIMIT 1000
), feedback_sample AS MATERIALIZED (
  SELECT i._idrref AS interaction_id
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= TIMESTAMP '2026-07-01'
    AND i._fld823 < TIMESTAMP '2026-08-01'
  ORDER BY i._fld823, i._idrref
  LIMIT 500
), comment_rows AS (
  SELECT f.interaction_id, h._idrref AS comment_id
  FROM feedback_sample f
  JOIN public._reference137 h ON h._fld1462rref = f.interaction_id
)
SELECT (SELECT count(*) FROM phone_sample) AS phone_rows,
       (SELECT count(DISTINCT (interaction_id, phone_reference_id, phone_event_id))
        FROM phone_sample) AS distinct_phone_child_keys,
       (SELECT count(*) FILTER (WHERE phone_reference_id IS NULL
                                  OR phone_event_id IS NULL)
        FROM phone_sample) AS phone_null_key_parts,
       (SELECT count(*) FROM comment_rows) AS comment_rows,
       (SELECT count(*) FILTER (WHERE comment_id IS NULL) FROM comment_rows)
         AS comment_null_key_parts;

-- CRM-TV04: deterministic technical order. The future feedback view uses
-- timestamp plus physical ID. July has an observed earliest-follow-up tie;
-- comments have no same-interaction timestamp tie in this bounded control.
WITH feedback_sample AS MATERIALIZED (
  SELECT i._idrref AS feedback_id,
         i._owneridrref AS task_id,
         i._fld823 AS created_at
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= TIMESTAMP '2026-07-01'
    AND i._fld823 < TIMESTAMP '2026-08-01'
  ORDER BY i._fld823, i._idrref
  LIMIT 500
), followup_candidates AS (
  SELECT f.feedback_id, x._idrref AS followup_id, x._fld823 AS followup_at
  FROM feedback_sample f
  JOIN public._reference67 x ON x._owneridrref = f.task_id
                           AND x._fld823 >= f.created_at
                           AND x._fld831rref <> decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
), earliest_followup AS (
  SELECT feedback_id, min(followup_at) AS followup_at
  FROM followup_candidates
  GROUP BY feedback_id
), followup_ties AS (
  SELECT c.feedback_id, count(*) AS tied_rows
  FROM followup_candidates c
  JOIN earliest_followup e ON e.feedback_id = c.feedback_id
                          AND e.followup_at = c.followup_at
  GROUP BY c.feedback_id
  HAVING count(*) > 1
), comment_ties AS (
  SELECT f.feedback_id, h._fld1463, count(*) AS tied_rows
  FROM feedback_sample f
  JOIN public._reference137 h ON h._fld1462rref = f.feedback_id
  WHERE h._fld1463 >= f.created_at
  GROUP BY f.feedback_id, h._fld1463
  HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM feedback_sample) AS feedback_sample_rows,
       (SELECT count(*) FROM followup_ties) AS earliest_followup_timestamp_ties,
       (SELECT count(*) FROM comment_ties) AS comment_timestamp_ties;

-- Guest outcome selection is intentionally not copied here. Its exact legacy
-- controls remain NV-V06 and NV-V09 in newcomer_guest_visits_2026-08-11.sql:
-- they preserve 8 latest-state ties and 128 client/date duplicate excess.
ROLLBACK;
