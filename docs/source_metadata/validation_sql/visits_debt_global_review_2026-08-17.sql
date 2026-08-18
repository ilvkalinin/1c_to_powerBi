-- Global read-only review: «Посещаемость клиентов с долгами».
-- Executed against gymdb as gymdb_readonly on 2026-08-17.
-- Results are aggregate snapshots and contain neither PII nor raw identifiers.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

-- DV-V01/DV-V04. Expected: physical movement key is unique and obligatory
-- client/prebooking attributes are present. A prebooking is not presumed to
-- identify one client; the confirmed as-of key remains client × prebooking.
WITH base AS MATERIALIZED (
  SELECT _period, _recordertref, _recorderrref, _lineno, _active,
         _fld7511rref AS client_id, _fld7512_rrref AS prebooking_id,
         _fld7516 AS quantity_delta, _fld7517 AS amount_delta
  FROM public._accumrg7509
  WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
), movement_clients AS (
  SELECT prebooking_id, client_id, count(*) AS movement_rows
  FROM base GROUP BY 1, 2
), crossing AS (
  SELECT prebooking_id, count(*) AS clients_per_prebooking
  FROM movement_clients GROUP BY 1 HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM base) AS movement_rows,
       (SELECT count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) FROM base) AS technical_keys,
       (SELECT count(*) FROM base WHERE NOT _active) AS inactive_rows,
       (SELECT count(*) FROM base WHERE client_id IS NULL) AS null_client_rows,
       (SELECT count(*) FROM base WHERE prebooking_id IS NULL) AS null_prebooking_rows,
       (SELECT count(*) FROM base WHERE quantity_delta IS NULL OR amount_delta IS NULL) AS null_quantity_or_amount_rows,
       (SELECT count(*) FROM movement_clients) AS client_prebooking_pairs,
       (SELECT count(*) FROM crossing) AS cross_client_prebookings,
       coalesce((SELECT max(clients_per_prebooking) FROM crossing), 0) AS max_clients_per_prebooking,
       (SELECT count(*) FROM movement_clients WHERE movement_rows > 1) AS pairs_with_multiple_movements;

-- DV-V02. Expected: the four current DAX classes are measured without adding
-- a meaning to quantities outside ±1.
SELECT _recordkind AS record_kind,
       CASE WHEN _fld7516 = 1 THEN 'plus_one'
            WHEN _fld7516 = -1 THEN 'minus_one'
            WHEN _fld7516 IS NULL THEN 'null' ELSE 'other' END AS quantity_class,
       count(*) AS movement_rows,
       count(*) FILTER (WHERE _fld7517 = 0) AS zero_amount_rows
FROM public._accumrg7509
WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
GROUP BY 1, 2 ORDER BY 1, 2;

-- DV-V03. Expected: preserve the current text predicate for observation and
-- measure branch loss/multiplication. Source mvarchar needs ::text solely for
-- PostgreSQL execution; this is not a replacement of the current Power Query.
WITH base AS MATERIALIZED (
  SELECT r._period, r._recordertref, r._recorderrref, r._lineno,
         r._fld7512_rrref AS prebooking_id
  FROM public._accumrg7509 r
  LEFT JOIN public._reference163 service ON service._idrref = r._fld7513rref
  WHERE r._period BETWEEN DATE '2026-01-01' AND DATE '2027-01-01'
    AND service._description::text NOT ILIKE 'Купон%'
), prebooking_branch AS (
  SELECT b._period, b._recordertref, b._recorderrref, b._lineno
  FROM base b LEFT JOIN public._document329 d ON d._idrref = b.prebooking_id
  INNER JOIN public._reference225 employee ON employee._idrref = d._fld4322rref
), group_branch AS (
  SELECT b._period, b._recordertref, b._recorderrref, b._lineno
  FROM base b INNER JOIN public._document279 d ON d._idrref = b.prebooking_id
  INNER JOIN public._reference225 employee ON employee._idrref = d._fld3223rref
), current_m_rows AS (
  SELECT * FROM prebooking_branch UNION ALL SELECT * FROM group_branch
)
SELECT (SELECT count(*) FROM base) AS base_rows,
       (SELECT count(*) FROM current_m_rows) AS current_m_branch_rows,
       (SELECT count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) FROM current_m_rows) AS distinct_current_m_keys,
       (SELECT count(*) FROM current_m_rows) - (SELECT count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) FROM current_m_rows) AS branch_join_excess,
       (SELECT count(*) FROM base) - (SELECT count(DISTINCT (_period, _recordertref, _recorderrref, _lineno)) FROM current_m_rows) AS movements_not_output_by_current_m;

-- DV-V06 observation. Direct ILIKE on 1C mvarchar is unsupported; cast is
-- recorded only to measure the source-side equivalent and never supplies a
-- new stable service classification.
WITH visits AS (
  SELECT a._period::date AS visit_date, a._fld7576rref AS client_id,
         a._fld7577rref AS movement_club_id, d._fld4167rref AS document_club_id,
         a._recordertref, a._recorderrref, a._lineno
  FROM public._accumrg7575 a
  LEFT JOIN public._reference163 service ON service._idrref = a._fld7579rref
  LEFT JOIN public._document325 d ON d._idrref = a._recorderrref
  WHERE a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01'
    AND service._description::text LIKE '%Посещение%'
)
SELECT count(*) AS current_m_visit_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS technical_visit_keys,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS visit_join_excess,
       count(DISTINCT (visit_date, client_id, document_club_id)) AS visit_client_day_club,
       count(*) FILTER (WHERE document_club_id IS NULL) AS missing_document_club,
       count(*) FILTER (WHERE movement_club_id IS DISTINCT FROM document_club_id) AS movement_vs_document_club_mismatch
FROM visits;

-- DV-V06B. Expected: measure, rather than assume, whether the legacy service
-- name predicate identifies the same visit movements as the existing exact
-- Document325 operation ID used by other visit reports. Any difference keeps
-- the legacy predicate in place until a business decision; this query creates
-- no new cohort filter.
WITH legacy_service AS MATERIALIZED (
  SELECT a._recordertref, a._recorderrref, a._lineno
  FROM public._accumrg7575 a
  JOIN public._reference163 s ON s._idrref = a._fld7579rref
  WHERE a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01'
    AND s._description::text LIKE '%Посещение%'
), operation_visit AS MATERIALIZED (
  SELECT a._recordertref, a._recorderrref, a._lineno
  FROM public._accumrg7575 a
  JOIN public._document325 d ON d._idrref = a._recorderrref
  WHERE a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01'
    AND d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
)
SELECT (SELECT count(*) FROM legacy_service) AS legacy_service_rows,
       (SELECT count(*) FROM operation_visit) AS operation_visit_rows,
       (SELECT count(*) FROM legacy_service l
        JOIN operation_visit o USING (_recordertref, _recorderrref, _lineno)) AS intersect_rows,
       (SELECT count(*) FROM legacy_service l
        LEFT JOIN operation_visit o USING (_recordertref, _recorderrref, _lineno)
        WHERE o._recorderrref IS NULL) AS legacy_only_rows,
       (SELECT count(*) FROM operation_visit o
        LEFT JOIN legacy_service l USING (_recordertref, _recorderrref, _lineno)
        WHERE l._recorderrref IS NULL) AS operation_only_rows;

ROLLBACK;
