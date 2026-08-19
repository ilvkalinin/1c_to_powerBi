-- DV-V05B: source-side as-of observation for «Посещаемость клиентов с долгами».
-- Runs on gymdb as gymdb_readonly in one REPEATABLE READ, READ ONLY snapshot.
-- Expected before execution:
--   * BR-025 returns at least two nonempty actual clubs for each control date;
--   * each selected date × club × client tuple is unique after client-day collapse;
--   * the document client is present and equals the movement client;
--   * the query reports only aggregate counts and sums, never source client IDs.
-- There is no independent Power BI control value. Therefore a nonempty result
-- records an OBSERVATION, not a reconciliation PASS for the final KPI.

BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

WITH raw_visits AS MATERIALIZED (
  SELECT a._period::date AS control_date,
         a._fld7576rref AS movement_client_id,
         d._fld4171rref AS document_client_id,
         d._fld4167rref AS club_id,
         a._recordertref,
         a._recorderrref,
         a._lineno
  FROM public._accumrg7575 a
  INNER JOIN public._document325 d ON d._idrref = a._recorderrref
  WHERE ((a._period >= TIMESTAMP '2026-07-15 00:00:00'
          AND a._period < TIMESTAMP '2026-07-16 00:00:00')
      OR (a._period >= TIMESTAMP '2026-08-15 00:00:00'
          AND a._period < TIMESTAMP '2026-08-16 00:00:00'))
    AND d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
), ranked_clubs AS MATERIALIZED (
  SELECT control_date, club_id,
         dense_rank() OVER (
           PARTITION BY control_date
           ORDER BY count(DISTINCT document_client_id) DESC, encode(club_id, 'hex')
         ) AS club_rank
  FROM raw_visits
  GROUP BY control_date, club_id
), selected_clubs AS MATERIALIZED (
  SELECT control_date, club_id, club_rank
  FROM ranked_clubs
  WHERE club_rank <= 2
), visit_client_day AS MATERIALIZED (
  SELECT rv.control_date, sc.club_rank, rv.club_id, rv.document_client_id AS client_id,
         count(*) AS raw_visit_events,
         count(*) FILTER (WHERE rv.document_client_id IS NULL)
           AS raw_events_without_document_client,
         count(*) FILTER (WHERE rv.movement_client_id IS DISTINCT FROM rv.document_client_id)
           AS raw_events_with_client_mismatch,
         count(DISTINCT (rv._recordertref, rv._recorderrref, rv._lineno))
           AS technical_visit_keys
  FROM raw_visits rv
  INNER JOIN selected_clubs sc
    ON sc.control_date = rv.control_date AND sc.club_id = rv.club_id
  GROUP BY rv.control_date, sc.club_rank, rv.club_id, rv.document_client_id
), selected_debt_movements AS MATERIALIZED (
  SELECT m._period AS movement_at,
         m._fld7511rref AS client_id,
         m._fld7512_rrref AS prebooking_id,
         m._recordkind AS record_kind,
         m._fld7516 AS quantity_delta,
         m._fld7517 AS amount_delta
  FROM public._accumrg7509 m
  WHERE m._period >= DATE '2026-01-01'
    AND m._period < DATE '2026-08-16'
    AND EXISTS (
      SELECT 1
      FROM visit_client_day selected_client
      WHERE selected_client.client_id = m._fld7511rref
    )
), debt_pairs AS MATERIALIZED (
  SELECT v.control_date, v.club_rank, v.club_id, v.client_id,
         m.prebooking_id,
         sum(m.amount_delta) FILTER (WHERE m.movement_at < v.control_date)
           AS start_amount,
         sum(m.amount_delta) FILTER (WHERE m.movement_at < v.control_date + INTERVAL '1 day')
           AS end_amount,
         sum(CASE WHEN (m.record_kind = 0 AND m.quantity_delta = 1)
                       OR (m.record_kind = 1 AND m.quantity_delta = 1)
                       OR (m.record_kind = 1 AND m.quantity_delta = -1)
                       OR (m.record_kind = 0 AND m.quantity_delta = -1)
                  THEN m.quantity_delta ELSE 0 END)
           FILTER (WHERE m.movement_at < v.control_date) AS start_unconfirmed,
         sum(CASE WHEN (m.record_kind = 0 AND m.quantity_delta = 1)
                       OR (m.record_kind = 1 AND m.quantity_delta = 1)
                       OR (m.record_kind = 1 AND m.quantity_delta = -1)
                       OR (m.record_kind = 0 AND m.quantity_delta = -1)
                  THEN m.quantity_delta ELSE 0 END)
           FILTER (WHERE m.movement_at < v.control_date + INTERVAL '1 day') AS end_unconfirmed
  FROM visit_client_day v
  LEFT JOIN selected_debt_movements m
    ON m.client_id = v.client_id
   AND m.movement_at < v.control_date + INTERVAL '1 day'
  GROUP BY v.control_date, v.club_rank, v.club_id, v.client_id, m.prebooking_id
), debt_clients AS (
  SELECT control_date, club_rank, club_id, client_id,
         count(*) FILTER (WHERE end_unconfirmed > 0) AS open_prebooking_pairs,
         coalesce(sum(end_amount) FILTER (WHERE end_unconfirmed > 0), 0)
           AS debt_amount_end_day
  FROM debt_pairs
  GROUP BY control_date, club_rank, club_id, client_id
)
SELECT v.control_date,
       v.club_rank,
       count(*) AS visit_client_days,
       sum(v.raw_visit_events) AS raw_visit_events,
       sum(v.raw_events_without_document_client) AS raw_events_without_document_client,
       sum(v.raw_events_with_client_mismatch) AS raw_events_with_client_mismatch,
       sum(v.raw_visit_events - v.technical_visit_keys) AS duplicate_technical_visit_keys,
       count(*) FILTER (WHERE d.open_prebooking_pairs > 0) AS visitors_with_open_debt,
       coalesce(sum(d.debt_amount_end_day), 0) AS debt_amount_end_day
FROM visit_client_day v
LEFT JOIN debt_clients d
  ON d.control_date = v.control_date
 AND d.club_rank = v.club_rank
 AND d.club_id = v.club_id
 AND d.client_id = v.client_id
GROUP BY v.control_date, v.club_rank
ORDER BY v.control_date, v.club_rank;

ROLLBACK;
