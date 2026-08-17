-- Global read-only review: «Новички и гостевые визиты».
-- Executed against gymdb as gymdb_readonly on 2026-08-17.
-- No statement returns PII or raw identifiers.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

-- NVG-V02. Bounded physical observation for the visit-document path.
-- Expected before any implementation: no unmatched document/contract or client
-- mismatch in the sampled current document path. This does not certify the full
-- first-visit filter or create a new filter.
WITH visit_docs AS MATERIALIZED (
  SELECT d._idrref AS visit_document_id, d._fld4171rref AS document_client_id
  FROM public._document325 d
  WHERE d._date_time >= DATE '2026-07-01' AND d._date_time < DATE '2026-08-01'
  ORDER BY d._date_time, d._idrref
  LIMIT 100
), movements AS (
  SELECT d.visit_document_id, d.document_client_id,
         a._recordertref, a._recorderrref, a._lineno,
         a._fld7576rref AS movement_client_id, a._fld7578_rrref AS contract_id
  FROM visit_docs d
  LEFT JOIN public._accumrg7575 a ON a._recorderrref = d.visit_document_id
)
SELECT
  (SELECT count(*) FROM visit_docs) AS sampled_visit_documents,
  count(*) FILTER (WHERE _recorderrref IS NOT NULL) AS linked_movement_rows,
  count(DISTINCT (_recordertref, _recorderrref, _lineno))
    FILTER (WHERE _recorderrref IS NOT NULL) AS linked_technical_keys,
  count(*) FILTER (WHERE _recorderrref IS NULL) AS documents_without_movement,
  count(*) FILTER (WHERE _recorderrref IS NOT NULL AND contract_id IS NULL) AS null_contract_rows,
  count(*) FILTER (WHERE _recorderrref IS NOT NULL
                    AND movement_client_id IS DISTINCT FROM document_client_id)
    AS client_mismatch_rows
FROM movements;

-- NVG-V06. Bounded observation of the physical dates used by the current
-- [0,44]-day rule. The report's exact eligible-contract filters are not
-- re-created here because their PBI source artifact is absent; this statement
-- must not be treated as a full reconciliation of purchase attribution.
WITH guest_sample AS MATERIALIZED (
  SELECT g._fld7065rref AS client_id, g._fld7068::date AS guest_visit_date
  FROM public._inforg7064 g
  WHERE g._period >= DATE '2026-07-01' AND g._period < DATE '2026-08-01'
  ORDER BY g._period, g._recorderrref, g._lineno
  LIMIT 100
), candidates AS (
  SELECT (r._fld670::date - g.guest_visit_date) AS lag_days
  FROM guest_sample g
  JOIN public._reference59 r
    ON r._fld681rref = g.client_id
   AND r._fld670::date >= g.guest_visit_date
   AND r._fld670::date <= g.guest_visit_date + 45
)
SELECT
  (SELECT count(*) FROM guest_sample) AS sampled_guest_rows,
  count(*) AS candidate_contract_rows_0_to_45,
  count(*) FILTER (WHERE lag_days = 0) AS lag_0_rows,
  count(*) FILTER (WHERE lag_days = 44) AS lag_44_rows,
  count(*) FILTER (WHERE lag_days = 45) AS lag_45_rows,
  count(*) FILTER (WHERE lag_days < 0 OR lag_days > 45) AS out_of_window_rows
FROM candidates;

ROLLBACK;
