-- SV-089: «Посещаемость клиентов с долгами» — read-only source validation.
-- Execute only against gymdb with gymdb_readonly. No query returns PII or raw IDs.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000';

-- DV-V01 expected: all current M relations exist; movement technical keys are
-- unique and its source flags are observed. This does not create a new filter.
SELECT count(*) AS existing_relations
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('_accumrg7509', '_accumrg7575', '_document325',
                    '_document329', '_document279', '_document313',
                    '_reference132', '_reference141x1', '_reference163',
                    '_reference225');

SELECT count(*) AS movement_rows,
       count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) AS technical_keys,
       count(*) - count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) AS duplicate_technical_keys,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE _fld7511rref IS NULL) AS null_client_rows,
       count(*) FILTER (WHERE _fld7512_rrref IS NULL) AS null_prebooking_rows,
       count(*) FILTER (WHERE _fld7516 IS NULL OR _fld7517 IS NULL) AS null_quantity_or_amount_rows
FROM public._accumrg7509
WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01';

-- DV-V02 expected: current M recorder and RecordKind classes are enumerated
-- without assigning a new meaning to previously unseen technical values.
SELECT substr(encode(_recordertref, 'hex'), 1, 8) AS recorder_type_prefix,
       _recordkind AS record_kind, _fld7516 AS quantity_delta,
       count(*) AS movement_rows
FROM public._accumrg7509
WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
GROUP BY 1, 2, 3
ORDER BY movement_rows DESC, 1, 2, 3;

-- DV-V03 expected: the exact two-branch current M path does not silently
-- multiply a register movement. The INNER employee joins are measured as row
-- loss, not treated as approved exclusions. Text filter and inclusive 2027-01-01
-- boundary intentionally reproduce current M for observation only.
WITH base AS MATERIALIZED (
  SELECT r._period, r._recordertref, r._recorderrref, r._lineno,
         r._fld7512_rrref AS prebooking_id
  FROM public._accumrg7509 r
  LEFT JOIN public._reference163 service ON service._idrref = r._fld7513rref
  WHERE r._period BETWEEN DATE '2026-01-01' AND DATE '2027-01-01'
    AND service._description NOT ILIKE 'Купон%'
), prebooking_branch AS (
  SELECT b._period, b._recordertref, b._recorderrref, b._lineno
  FROM base b
  LEFT JOIN public._document329 d ON d._idrref = b.prebooking_id
  INNER JOIN public._reference225 employee ON employee._idrref = d._fld4322rref
), group_branch AS (
  SELECT b._period, b._recordertref, b._recorderrref, b._lineno
  FROM base b
  INNER JOIN public._document279 d ON d._idrref = b.prebooking_id
  INNER JOIN public._reference225 employee ON employee._idrref = d._fld3223rref
), current_m_rows AS (
  SELECT * FROM prebooking_branch UNION ALL SELECT * FROM group_branch
)
SELECT (SELECT count(*) FROM base) AS base_rows,
       (SELECT count(*) FROM current_m_rows) AS current_m_branch_rows,
       (SELECT count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) FROM current_m_rows) AS distinct_current_m_keys,
       (SELECT count(*) FROM current_m_rows)
         - (SELECT count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) FROM current_m_rows) AS branch_join_excess,
       (SELECT count(*) FROM base)
         - (SELECT count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) FROM current_m_rows) AS movements_not_output_by_current_m;

-- DV-V04 expected: a prebooking never crosses clients in the measured source.
-- Duplicates within a client/prebooking pair are allowed movements and are
-- counted rather than deduplicated.
WITH movement_clients AS (
  SELECT _fld7512_rrref AS prebooking_id, _fld7511rref AS client_id,
         count(*) AS movement_rows
  FROM public._accumrg7509
  WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
  GROUP BY 1, 2
), crossing AS (
  SELECT prebooking_id, count(*) AS clients_per_prebooking
  FROM movement_clients GROUP BY 1 HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM movement_clients) AS client_prebooking_pairs,
       (SELECT count(*) FROM crossing) AS cross_client_prebookings,
       coalesce((SELECT max(clients_per_prebooking) FROM crossing), 0) AS max_clients_per_prebooking,
       (SELECT count(*) FROM movement_clients WHERE movement_rows > 1) AS pairs_with_multiple_movements;

-- DV-V06 expected: current visit population is measured separately from debt
-- movements. It intentionally preserves the M text filter and no state filter;
-- the output contains only aggregate keys and establishes whether the visit
-- document join multiplies source movement rows.
WITH visits AS (
  SELECT a._period::date AS visit_date, a._fld7576rref AS client_id,
         a._fld7577rref AS movement_club_id, d._fld4167rref AS document_club_id,
         a._recordertref, a._recorderrref, a._lineno
  FROM public._accumrg7575 a
  LEFT JOIN public._reference163 service ON service._idrref = a._fld7579rref
  LEFT JOIN public._document325 d ON d._idrref = a._recorderrref
  WHERE a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01'
    AND service._description LIKE '%Посещение%'
)
SELECT count(*) AS current_m_visit_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS technical_visit_keys,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS visit_join_excess,
       count(DISTINCT (visit_date, client_id, document_club_id)) AS visit_client_day_club,
       count(*) FILTER (WHERE document_club_id IS NULL) AS missing_document_club,
       count(*) FILTER (WHERE movement_club_id IS DISTINCT FROM document_club_id) AS movement_vs_document_club_mismatch
FROM visits;

ROLLBACK;
