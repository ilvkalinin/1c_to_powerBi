-- Global read-only review: «Отчёт по обращениям».
-- Executed against gymdb as gymdb_readonly on 2026-08-17.
-- Results are aggregate live-source snapshots; no statement returns PII or IDs.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

-- CR-V03 correction. Expected: count only real phone rows/keys; a null
-- placeholder introduced by LEFT JOIN is not a technical key.
WITH feedback AS MATERIALIZED (
  SELECT i._idrref AS interaction_id
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01' AND i._fld823 < DATE '2027-01-01'
), phone_counts AS (
  SELECT f.interaction_id, count(p._fld7151rref) AS phone_rows,
         count(DISTINCT (p._fld7147rref, p._fld8699))
           FILTER (WHERE p._fld7151rref IS NOT NULL) AS phone_technical_keys
  FROM feedback f
  LEFT JOIN public._inforg7146 p ON p._fld7151rref = f.interaction_id
  GROUP BY f.interaction_id
), html_counts AS (
  SELECT f.interaction_id, count(h._idrref) AS html_rows
  FROM feedback f
  LEFT JOIN public._reference137 h ON h._fld1462rref = f.interaction_id
  GROUP BY f.interaction_id
)
SELECT (SELECT count(*) FROM feedback) AS feedback_interactions,
       (SELECT coalesce(sum(phone_rows), 0) FROM phone_counts) AS phone_rows,
       (SELECT coalesce(sum(phone_technical_keys), 0) FROM phone_counts) AS phone_technical_keys,
       (SELECT count(*) FROM phone_counts WHERE phone_rows > 1) AS multi_phone_interactions,
       (SELECT coalesce(max(phone_rows), 0) FROM phone_counts) AS max_phone_rows,
       (SELECT coalesce(sum(html_rows), 0) FROM html_counts) AS html_rows,
       (SELECT count(*) FROM html_counts WHERE html_rows > 1) AS multi_html_interactions,
       (SELECT coalesce(max(html_rows), 0) FROM html_counts) AS max_html_rows;

-- CR-V06. Expected: the bounded current task-owner path has no earlier
-- follow-up; timestamp then physical ID gives deterministic first event.
WITH feedback AS MATERIALIZED (
  SELECT i._idrref AS feedback_id, i._owneridrref AS task_id, i._fld823 AS created_at
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01' AND i._fld823 < DATE '2027-01-01'
  ORDER BY i._fld823, i._idrref
  LIMIT 100
), examined AS (
  SELECT f.feedback_id, f.created_at, o.followup_created_at,
         o.same_timestamp_candidates
  FROM feedback f
  LEFT JOIN LATERAL (
    SELECT x._fld823 AS followup_created_at,
           count(*) FILTER (WHERE x._fld823 = f.created_at) OVER () AS same_timestamp_candidates
    FROM public._reference67 x
    WHERE x._owneridrref = f.task_id AND x._fld823 >= f.created_at
      AND x._fld831rref <> decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    ORDER BY x._fld823, x._idrref
    LIMIT 1
  ) o ON TRUE
)
SELECT count(*) AS sampled_feedback,
       count(*) FILTER (WHERE followup_created_at IS NULL) AS no_followup,
       count(*) FILTER (WHERE followup_created_at < created_at) AS invalid_precreation_followup,
       count(*) FILTER (WHERE same_timestamp_candidates > 1) AS ambiguous_same_timestamp_ties
FROM examined;

ROLLBACK;
