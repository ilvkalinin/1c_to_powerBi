-- SV-088: «Отчёт по обращениям» — read-only source validation.
-- Execute only against gymdb with gymdb_readonly. No query returns PII or raw IDs.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000';

-- CR-V01 expected: all relations used by the confirmed current source paths
-- are present in public. This establishes availability only; it does not turn
-- undocumented source flags into a first-release filter.
SELECT count(*) AS existing_relations
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('_reference67', '_reference106', '_inforg7146',
                    '_reference137', '_reference8628', '_reference89',
                    '_reference132', '_reference178', '_reference224',
                    '_reference225', '_reference101', '_reference141x1',
                    '_reference145', '_reference122', '_reference212',
                    '_reference202', '_accumrg7575', '_document325',
                    '_reference59');

-- CR-V02 expected: every feedback row is one physical interaction and its
-- required task exists. Duplicate task/client codes are observed separately:
-- current follow-up attribution uses codes and must not be silently promoted
-- to an ID-based rule.
WITH feedback AS MATERIALIZED (
  SELECT i._idrref AS interaction_id, i._owneridrref AS task_id,
         i._fld823 AS created_at
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01'
    AND i._fld823 < DATE '2027-01-01'
)
SELECT count(*) AS feedback_rows,
       count(DISTINCT interaction_id) AS distinct_interactions,
       count(*) - count(DISTINCT interaction_id) AS duplicate_interaction_ids,
       count(*) FILTER (WHERE t._idrref IS NULL) AS orphan_task_rows,
       count(*) FILTER (WHERE f.created_at IS NULL) AS null_created_at_rows,
       count(*) FILTER (WHERE f.created_at > CURRENT_TIMESTAMP) AS future_created_at_rows
FROM feedback f
LEFT JOIN public._reference106 t ON t._idrref = f.task_id;

-- CR-V03 expected: phone and HTML are not assumed one-to-one. Their technical
-- multiplicity is measured before any aggregation; no report-level DISTINCT
-- is introduced by this check.
WITH feedback AS MATERIALIZED (
  SELECT i._idrref AS interaction_id
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01'
    AND i._fld823 < DATE '2027-01-01'
), phone_counts AS (
  SELECT f.interaction_id, count(p._fld7151rref) AS phone_rows,
         count(DISTINCT (p._fld7147rref, p._fld8699)) AS phone_technical_keys
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

-- CR-V04 expected: current task dimensions are left joins and may be absent;
-- the dimension PK side must not multiply an interaction. The check returns
-- only counts and is not a decision to filter unmatched rows.
WITH feedback AS MATERIALIZED (
  SELECT i._idrref AS interaction_id, i._owneridrref AS task_id
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01'
    AND i._fld823 < DATE '2027-01-01'
), joined AS (
  SELECT f.interaction_id, t._idrref AS task_match_id,
         funnel._idrref AS funnel_match_id, club._idrref AS club_match_id,
         client._idrref AS client_match_id
  FROM feedback f
  LEFT JOIN public._reference106 t ON t._idrref = f.task_id
  LEFT JOIN public._reference89 funnel ON funnel._idrref = t._fld1191rref
  LEFT JOIN public._reference132 club ON club._idrref = t._fld1195rref
  LEFT JOIN public._reference141x1 client ON client._idrref = t._fld1196rref
)
SELECT count(*) AS joined_rows,
       count(DISTINCT interaction_id) AS distinct_interactions,
       count(*) - count(DISTINCT interaction_id) AS dimension_join_excess,
       count(*) FILTER (WHERE task_match_id IS NULL) AS missing_task,
       count(*) FILTER (WHERE funnel_match_id IS NULL) AS missing_funnel,
       count(*) FILTER (WHERE club_match_id IS NULL) AS missing_club,
       count(*) FILTER (WHERE client_match_id IS NULL) AS missing_client
FROM joined;

-- CR-V06 expected: the current rule is measured exactly as the first later
-- non-feedback interaction for the same task. It is deliberately not renamed
-- to a telephone call. The 100-row bounded sample makes the pairwise check
-- safe for the live source and reports ties deterministically.
WITH feedback AS MATERIALIZED (
  SELECT i._idrref AS feedback_id, i._owneridrref AS task_id, i._fld823 AS created_at
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01'
    AND i._fld823 < DATE '2027-01-01'
  ORDER BY i._idrref
  LIMIT 100
), candidates AS (
  SELECT f.feedback_id, f.created_at, o._idrref AS followup_id, o._fld823 AS followup_created_at,
         row_number() OVER (PARTITION BY f.feedback_id ORDER BY o._fld823, o._idrref) AS rn,
         count(*) FILTER (WHERE o._fld823 = f.created_at)
           OVER (PARTITION BY f.feedback_id) AS same_timestamp_candidates
  FROM feedback f
  LEFT JOIN public._reference67 o
    ON o._owneridrref = f.task_id
   AND o._fld823 >= f.created_at
   AND o._fld831rref <> decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
), first_followup AS (
  SELECT feedback_id, created_at, followup_id, followup_created_at, same_timestamp_candidates
  FROM candidates WHERE rn = 1
)
SELECT (SELECT count(*) FROM feedback) AS sampled_feedback,
       count(*) FILTER (WHERE followup_id IS NULL) AS no_followup,
       count(*) FILTER (WHERE followup_created_at < created_at) AS invalid_precreation_followup,
       count(*) FILTER (WHERE same_timestamp_candidates > 1) AS ambiguous_same_timestamp_ties
FROM first_followup;

-- CR-V07 expected: comment updates used by current COALESCE never precede the
-- feedback creation. Multiple post-creation comments are observed and require
-- the existing MIN(timestamp) aggregation; their text is never selected.
WITH feedback AS MATERIALIZED (
  SELECT i._idrref AS interaction_id, i._fld823 AS created_at
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01'
    AND i._fld823 < DATE '2027-01-01'
  ORDER BY i._idrref
  LIMIT 100
), comments AS (
  SELECT f.interaction_id,
         count(h._idrref) FILTER (WHERE h._fld1463 > f.created_at) AS post_creation_comments,
         count(h._idrref) FILTER (WHERE h._fld1463 < f.created_at) AS pre_creation_comments,
         count(h._idrref) FILTER (WHERE h._fld1463 = f.created_at) AS same_timestamp_comments
  FROM feedback f
  LEFT JOIN public._reference137 h ON h._fld1462rref = f.interaction_id
  GROUP BY f.interaction_id
)
SELECT count(*) AS sampled_feedback,
       count(*) FILTER (WHERE post_creation_comments > 1) AS multi_post_creation_comments,
       count(*) FILTER (WHERE pre_creation_comments > 0) AS feedback_with_precreation_comment,
       count(*) FILTER (WHERE same_timestamp_comments > 1) AS ambiguous_same_timestamp_comment_ties,
       coalesce(max(post_creation_comments), 0) AS max_post_creation_comments
FROM comments;

-- CR-V09 expected: current source state flags are measured but never used to
-- introduce a new filter under BR-018. A future date and deletion observation
-- are evidence, not a correction to the report.
SELECT count(*) AS feedback_2026,
       count(*) FILTER (WHERE _marked) AS marked_feedback,
       count(*) FILTER (WHERE _fld9074) AS archived_feedback,
       count(*) FILTER (WHERE _fld823 > CURRENT_TIMESTAMP) AS future_feedback
FROM public._reference67
WHERE _fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
  AND _fld823 >= DATE '2026-01-01'
  AND _fld823 < DATE '2027-01-01';

ROLLBACK;
