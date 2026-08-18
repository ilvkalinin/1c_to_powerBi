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

-- CR-V05A. Expected: all six documented topics and five documented funnels
-- exist once in their reference tables. The feedback scope keeps a physical
-- interaction grain and does not introduce a new filter beyond the report's
-- documented names.
WITH requested_topics(topic_name) AS (
  VALUES ('Благодарность'), ('Замечание'), ('Консультация'),
         ('Предложение'), ('Пропажа'), ('Травма')
), requested_funnels(funnel_name) AS (
  VALUES ('Продажа клубной карты'), ('Сервисный звонок'),
         ('Корпоративная продажа'), ('Сервисная воронка ОП'),
         ('Продажа клип-карт Рецепция')
), topic_matches AS (
  SELECT q.topic_name, count(t._idrref) AS physical_matches
  FROM requested_topics q
  LEFT JOIN public._reference8628 t ON t._description::text = q.topic_name
  GROUP BY 1
), funnel_matches AS (
  SELECT q.funnel_name, count(f._idrref) AS physical_matches
  FROM requested_funnels q
  LEFT JOIN public._reference89 f ON f._description::text = q.funnel_name
  GROUP BY 1
), scoped_feedback AS (
  SELECT i._idrref AS interaction_id
  FROM public._reference67 i
  JOIN public._reference106 task ON task._idrref = i._owneridrref
  JOIN public._reference8628 topic ON topic._idrref = task._fld8643rref
  JOIN public._reference89 funnel ON funnel._idrref = task._fld1191rref
  JOIN requested_topics rt ON rt.topic_name = topic._description::text
  JOIN requested_funnels rf ON rf.funnel_name = funnel._description::text
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-01-01' AND i._fld823 < DATE '2027-01-01'
)
SELECT (SELECT count(*) FROM topic_matches WHERE physical_matches = 1) AS topics_with_one_match,
       (SELECT count(*) FROM topic_matches WHERE physical_matches = 0) AS missing_topics,
       (SELECT count(*) FROM funnel_matches WHERE physical_matches = 1) AS funnels_with_one_match,
       (SELECT count(*) FROM funnel_matches WHERE physical_matches = 0) AS missing_funnels,
       (SELECT count(*) FROM scoped_feedback) AS scoped_feedback_rows,
       (SELECT count(DISTINCT interaction_id) FROM scoped_feedback) AS scoped_feedback_ids,
       (SELECT count(*) FROM scoped_feedback) - (SELECT count(DISTINCT interaction_id) FROM scoped_feedback) AS scope_join_excess;

-- CR-V05A executed separately on 2026-08-18. The narrow reference control is
-- retained separately because it does not replace the later scoped-feedback
-- cardinality check.
WITH requested_topics(topic_name) AS (
  VALUES ('Благодарность'), ('Замечание'), ('Консультация'),
         ('Предложение'), ('Пропажа'), ('Травма')
), requested_funnels(funnel_name) AS (
  VALUES ('Продажа клубной карты'), ('Сервисный звонок'),
         ('Корпоративная продажа'), ('Сервисная воронка ОП'),
         ('Продажа клип-карт Рецепция')
), topic_matches AS (
  SELECT q.topic_name, count(t._idrref) AS physical_matches
  FROM requested_topics q
  LEFT JOIN public._reference8628 t ON t._description::text = q.topic_name
  GROUP BY 1
), funnel_matches AS (
  SELECT q.funnel_name, count(f._idrref) AS physical_matches
  FROM requested_funnels q
  LEFT JOIN public._reference89 f ON f._description::text = q.funnel_name
  GROUP BY 1
)
SELECT (SELECT count(*) FROM topic_matches WHERE physical_matches = 1) AS topics_with_one_match,
       (SELECT count(*) FROM topic_matches WHERE physical_matches = 0) AS missing_topics,
       (SELECT count(*) FROM funnel_matches WHERE physical_matches = 1) AS funnels_with_one_match,
       (SELECT count(*) FROM funnel_matches WHERE physical_matches = 0) AS missing_funnels;

-- CR-V05B, executed 2026-08-18. This observation may identify a renamed or
-- differently punctuated candidate, but it must not substitute the documented
-- funnel name without the current SQL/M/DAX rule.
SELECT _description::text AS funnel_name
FROM public._reference89
WHERE _description::text ILIKE '%клип%'
ORDER BY 1;

-- CR-V05C, executed 2026-08-18. A bounded July impact observation for the
-- CR-V05B candidate only. It does not adopt the candidate into the report
-- filter and does not generalise the one-month count to other periods.
WITH requested_topics(topic_name) AS (
  VALUES ('Благодарность'), ('Замечание'), ('Консультация'),
         ('Предложение'), ('Пропажа'), ('Травма')
), feedback AS MATERIALIZED (
  SELECT i._idrref, i._owneridrref
  FROM public._reference67 i
  WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
    AND i._fld823 >= DATE '2026-07-01' AND i._fld823 < DATE '2026-08-01'
)
SELECT count(*) AS scoped_feedback_rows,
       count(DISTINCT f._idrref) AS scoped_feedback_ids
FROM feedback f
JOIN public._reference106 task ON task._idrref = f._owneridrref
JOIN public._reference8628 topic ON topic._idrref = task._fld8643rref
JOIN public._reference89 funnel ON funnel._idrref = task._fld1191rref
JOIN requested_topics rt ON rt.topic_name = topic._description::text
WHERE funnel._description::text = 'Продажа клип карты Рецепция';

-- CR-V05D. Confirmed by BR-023 on 2026-08-18: the report label resolves to
-- this one physical funnel ID. Future source filters use the ID rather than a
-- text comparison; no other similarly named funnel is implied.
SELECT count(*) AS resolved_funnel_rows,
       count(*) FILTER (
         WHERE _description::text = 'Продажа клип карты Рецепция'
       ) AS expected_source_name_rows
FROM public._reference89
WHERE _idrref = decode('99d7928e75e3805f11f0310981642c71', 'hex');

-- CR-V05E, executed 2026-08-18. Bounded July control for the current Jivo
-- exclusion. It observes the existing text predicate; it neither replaces it
-- with another rule nor generalises the monthly count to the full history.
SELECT count(*) AS feedback_rows,
       count(*) FILTER (WHERE _description::text LIKE '%Jivo%') AS jivo_named_rows,
       count(*) FILTER (WHERE _description IS NULL) AS null_description_rows
FROM public._reference67
WHERE _fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
  AND _fld823 >= DATE '2026-07-01'
  AND _fld823 < DATE '2026-08-01';

-- CR-V05F, executed 2026-08-18. Bounded status-structure observation: it
-- counts physical values but does not assign report labels to their IDs.
SELECT count(*) AS feedback_rows,
       count(DISTINCT _fld830rref) AS nonnull_status_values,
       count(*) FILTER (WHERE _fld830rref IS NULL) AS null_status_rows
FROM public._reference67
WHERE _fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
  AND _fld823 >= DATE '2026-07-01'
  AND _fld823 < DATE '2026-08-01';

-- CR-V05G, executed 2026-08-18 as seven independent monthly transactions.
-- The date index makes each closed month selective; do not replace this with
-- an annual text scan. Run once for each [start_date, end_date) pair.
SELECT count(*) AS feedback_rows,
       count(*) FILTER (WHERE _description::text LIKE '%Jivo%') AS jivo_named_rows,
       count(DISTINCT _fld830rref) AS nonnull_status_values,
       count(*) FILTER (WHERE _fld830rref IS NULL) AS null_status_rows
FROM public._reference67
WHERE _fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
  AND _fld823 >= :start_date
  AND _fld823 < :end_date;

-- CR-V05H. Exact report-status mapping is preserved from current SQL. This
-- control is deliberately narrow and may be rerun only when a new snapshot is
-- needed; it never derives names from the unavailable enum relation.
SELECT count(*) AS feedback_rows,
       count(*) FILTER (WHERE _fld830rref = decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex')) AS completed_rows,
       count(*) FILTER (WHERE _fld830rref = decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex')) AS not_completed_rows,
       count(*) FILTER (WHERE _fld830rref = decode('aef6c17befe0705047f834208813539a', 'hex')) AS cancelled_rows,
       count(*) FILTER (WHERE _fld830rref IS NULL OR _fld830rref NOT IN (
         decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex'),
         decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex'),
         decode('aef6c17befe0705047f834208813539a', 'hex')
       )) AS unmapped_or_null_rows
FROM public._reference67
WHERE _fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
  AND _fld823 >= DATE '2026-01-01'
  AND _fld823 < DATE '2026-08-01';

ROLLBACK;
