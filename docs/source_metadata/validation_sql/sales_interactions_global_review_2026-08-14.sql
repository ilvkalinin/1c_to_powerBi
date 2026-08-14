-- SV-093. Read-only completion of the outstanding «Загрузка ОП» controls.
-- Run only on gymdb as gymdb_readonly; returns aggregates, never PII or raw IDs.
-- The sample starts from the three qualifying funnels so the indexed
-- task-owner path is used; no ordering is needed to test the stated invariants.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

-- SA-V02: 100 qualifying interactions; each non-null phone technical key is
-- counted once.  The FILTER is essential: a LEFT JOIN placeholder is not a
-- phone technical key.
WITH tasks AS MATERIALIZED (
    SELECT _idrref
    FROM public._reference106
    WHERE _fld1191rref IN (
        decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
        decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
        decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
    )
      AND NOT (
        _fld1191rref = decode('99b0e03a7af94bc911ef0167b7844d74', 'hex')
        AND _fld1197rref IN (
            decode('99e886b88886661011f0ae4e3da6296e', 'hex'),
            decode('99cc8098b8acd0e411efe53f048393c3', 'hex')
        )
      )
), base AS MATERIALIZED (
    SELECT i._idrref AS interaction_id
    FROM tasks t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    WHERE i._fld823 >= DATE '2026-01-01'
      AND i._fld823 < DATE '2027-01-01'
    LIMIT 100
), phone_rows AS (
    SELECT b.interaction_id,
           count(p._fld7151rref) AS phone_rows,
           count(DISTINCT (p._fld7147rref, p._fld8699))
             FILTER (WHERE p._fld7151rref IS NOT NULL) AS phone_technical_keys
    FROM base b
    LEFT JOIN public._inforg7146 p ON p._fld7151rref = b.interaction_id
    GROUP BY b.interaction_id
)
SELECT (SELECT count(*) FROM base) AS sampled_interactions,
       coalesce(sum(phone_rows), 0) AS phone_rows,
       coalesce(sum(phone_technical_keys), 0) AS phone_technical_keys,
       count(*) FILTER (WHERE phone_rows > 1) AS multi_phone_interactions,
       coalesce(max(phone_rows), 0) AS max_phone_rows
FROM phone_rows;

-- SA-V03: current name-and-date employment semijoin. Multiple matches are
-- observed but cannot multiply a report interaction because implementation
-- keeps EXISTS.
WITH tasks AS MATERIALIZED (
    SELECT _idrref FROM public._reference106
    WHERE _fld1191rref IN (
        decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
        decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
        decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
    )
), base AS MATERIALIZED (
    SELECT i._idrref AS interaction_id, i._fld823 AS created_at,
           m._description AS manager_name
    FROM tasks t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    LEFT JOIN public._reference225 m ON m._idrref = i._fld824rref
    WHERE i._fld823 >= DATE '2026-01-01'
      AND i._fld823 < DATE '2027-01-01'
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

-- SA-V04: observation only; do not derive a new marked/archive filter.
SELECT count(*) AS interactions_2026,
       count(*) FILTER (WHERE _marked) AS marked_interactions_2026
FROM public._reference67
WHERE _fld823 >= DATE '2026-01-01'
  AND _fld823 < DATE '2027-01-01';

ROLLBACK;
