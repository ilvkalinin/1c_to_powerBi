-- SV-084. Read-only bounded source validation for «Загрузка ОП».
-- Execute only against gymdb with gymdb_readonly. No PII or raw IDs are returned.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000';

-- SA-V01 expected: all five confirmed source relations exist in public.
SELECT count(*) AS existing_relations
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('_reference67', '_reference106', '_inforg7146',
                    '_inforg6291', '_reference225');

-- SA-V02 expected: exactly 100 bounded legacy-filter interactions are sampled;
-- phone technical keys are unique and any >1 phone rows per interaction are
-- preserved as separate report-compatible calls, as confirmed by SV-026.
WITH base AS MATERIALIZED (
  SELECT i._idrref AS interaction_id
  FROM public._reference67 i
  JOIN public._reference106 t ON t._idrref = i._owneridrref
  WHERE i._fld823 >= DATE '2026-01-01'
    AND i._fld823 < DATE '2027-01-01'
    AND t._fld1191rref IN (
      decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
      decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
      decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
    )
    AND NOT (
      t._fld1191rref = decode('99b0e03a7af94bc911ef0167b7844d74', 'hex')
      AND t._fld1197rref IN (
        decode('99e886b88886661011f0ae4e3da6296e', 'hex'),
        decode('99cc8098b8acd0e411efe53f048393c3', 'hex')
      )
    )
  ORDER BY i._idrref
  LIMIT 100
), phone_per_interaction AS (
  SELECT b.interaction_id,
         count(p._fld7151rref) AS phone_rows,
         count(DISTINCT (p._fld7147rref, p._fld8699)) AS phone_technical_keys
  FROM base b
  LEFT JOIN public._inforg7146 p ON p._fld7151rref = b.interaction_id
  GROUP BY b.interaction_id
)
SELECT (SELECT count(*) FROM base) AS sampled_interactions,
       coalesce(sum(phone_rows), 0) AS phone_rows,
       coalesce(sum(phone_technical_keys), 0) AS phone_technical_keys,
       count(*) FILTER (WHERE phone_rows > 1) AS multi_phone_interactions,
       coalesce(max(phone_rows), 0) AS max_phone_rows
FROM phone_per_interaction;

-- SA-V03 expected: the base has 100 interaction IDs.  The distribution of
-- qualifying legacy name-based employment rows is observed; EXISTS is the
-- report-compatible semijoin and therefore cannot multiply a base interaction.
WITH base AS MATERIALIZED (
  SELECT i._idrref AS interaction_id, i._fld823 AS created_at,
         m._description AS manager_name
  FROM public._reference67 i
  JOIN public._reference106 t ON t._idrref = i._owneridrref
  LEFT JOIN public._reference225 m ON m._idrref = i._fld824rref
  WHERE i._fld823 >= DATE '2026-01-01'
    AND i._fld823 < DATE '2027-01-01'
    AND t._fld1191rref IN (
      decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
      decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
      decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
    )
  ORDER BY i._idrref
  LIMIT 100
), employment_matches AS (
  SELECT b.interaction_id, count(*) AS employment_rows
  FROM base b
  JOIN public._inforg6291 h
    ON h._fld6298 <= b.created_at
   AND coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01 00:00:00'),
                TIMESTAMP '2099-12-31 00:00:00') >= b.created_at
  JOIN public._reference225 e ON e._idrref = h._fld6292rref
  JOIN public._reference101 p ON p._idrref = h._fld6296rref
  WHERE e._description = b.manager_name
    AND p._description IN ('Менеджер ОП', 'Старший менеджер ОП')
  GROUP BY b.interaction_id
)
SELECT (SELECT count(*) FROM base) AS sampled_interactions,
       count(*) AS interactions_with_employment,
       count(*) FILTER (WHERE employment_rows = 1) AS one_match,
       count(*) FILTER (WHERE employment_rows > 1) AS multi_match_interactions,
       coalesce(max(employment_rows), 0) AS max_employment_rows,
       (SELECT count(*) FROM base) - count(*) AS no_employment_match
FROM employment_matches;

-- SA-V04 expected: state flags are observations only.  Their values must not
-- introduce a new first-release filter without an explicit decision under BR-018.
SELECT count(*) AS interactions_2026,
       count(*) FILTER (WHERE _marked) AS marked_interactions_2026
FROM public._reference67
WHERE _fld823 >= DATE '2026-01-01'
  AND _fld823 < DATE '2027-01-01';

ROLLBACK;
