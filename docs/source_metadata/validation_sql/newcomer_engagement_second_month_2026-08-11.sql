-- SV-076: «Вовлечение новичков Второй месяц» — read-only source validation.
-- Execute in BEGIN TRANSACTION READ ONLY.  Results are live MVCC snapshots.

-- NM-V01: required physical relations.
SELECT c.relname, c.relkind
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = ANY (ARRAY['_reference59','_reference141x1','_reference163',
      '_reference87','_document346','_document346_vt4913','_inforg5654',
      '_accumrg7575','_inforg7006','_document329','_document325'])
ORDER BY c.relname;

-- NM-V02/V03: contract technical IDs, boundaries and visit → contract/client link.
SELECT count(*) AS rows, count(DISTINCT _idrref) AS ids,
       count(*) FILTER (WHERE _fld681rref IS NULL) AS null_client,
       count(*) FILTER (WHERE _fld671 IS NULL OR _fld672 IS NULL) AS null_boundary,
       count(*) FILTER (WHERE _fld672::date <= _fld671::date) AS nonpositive,
       count(*) FILTER (WHERE _fld693 <= 30) AS duration_le_30,
       count(*) FILTER (WHERE _marked) AS marked
FROM public._reference59
WHERE _fld671 >= DATE '2023-12-01';

SELECT count(*) AS rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS technical_keys,
       count(*) FILTER (WHERE r._idrref IS NULL) AS contract_orphans,
       count(*) FILTER (WHERE a._fld7576rref IS NULL) AS null_client,
       count(*) FILTER (WHERE r._idrref IS NOT NULL
                           AND a._fld7576rref <> r._fld681rref) AS client_owner_mismatch
FROM public._accumrg7575 a
LEFT JOIN public._reference59 r ON r._idrref = a._fld7578_rrref
WHERE a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01';

-- NM-V05/V06/V07: child package joins, duplicate candidate pairs and tenure ties.
SELECT count(*) AS rows,
       count(DISTINCT (v._document346_idrref, v._lineno4914)) AS technical_keys,
       count(*) FILTER (WHERE v._fld4916rref IS NULL) AS null_child,
       count(*) FILTER (WHERE ch._idrref IS NULL AND v._fld4916rref IS NOT NULL) AS child_orphans,
       count(*) FILTER (WHERE d._idrref IS NULL) AS receipt_orphans,
       count(*) FILTER (WHERE c._idrref IS NOT NULL) AS contract_hits
FROM public._document346_vt4913 v
LEFT JOIN public._reference141x1 ch ON ch._idrref = v._fld4916rref
LEFT JOIN public._document346 d ON d._idrref = v._document346_idrref
LEFT JOIN public._reference59 c ON c._idrref = v._fld4915rref;

SELECT count(*) AS duplicate_groups, coalesce(sum(n), 0) AS duplicate_rows,
       coalesce(max(n), 0) AS max_multiplicity
FROM (
    SELECT _fld4915rref, _fld4916rref, count(*) AS n
    FROM public._document346_vt4913
    GROUP BY 1, 2 HAVING count(*) > 1
) q;

SELECT count(*) AS rows,
       count(*) FILTER (WHERE _fld5655rref IS NULL) AS null_client,
       count(*) FILTER (WHERE _fld5656rref IS NULL) AS null_tenure,
       (SELECT count(*) FROM (
            SELECT _fld5655rref, _period, count(*) AS n
            FROM public._inforg5654 GROUP BY 1,2 HAVING count(*) > 1
       ) q) AS same_client_period_groups
FROM public._inforg5654;

-- NM-V08: bounded source-side control sample.  March 2026 starts must yield
-- [2026-04-01, 2026-05-01); no identifiers are returned.
WITH candidates AS MATERIALIZED (
    SELECT _idrref AS contract_id, _fld681rref AS client_id,
           (date_trunc('month', _fld671::date) + INTERVAL '1 month')::date AS month_start,
           (date_trunc('month', _fld671::date) + INTERVAL '2 month')::date AS month_end
    FROM public._reference59
    WHERE _fld671 >= DATE '2026-03-01' AND _fld671 < DATE '2026-04-01'
      AND _fld672::date > _fld671::date AND _fld693 > 30 AND _fld681rref IS NOT NULL
    ORDER BY _idrref LIMIT 100
), agg AS (
    SELECT c.contract_id, c.client_id, c.month_start, c.month_end,
           count(a._period) AS visit_rows, max(a._period::date) AS last_visit
    FROM candidates c
    LEFT JOIN public._accumrg7575 a
      ON a._fld7578_rrref = c.contract_id AND a._fld7576rref = c.client_id
     AND a._period >= c.month_start AND a._period < c.month_end
    GROUP BY 1,2,3,4
)
SELECT (SELECT count(*) FROM candidates) AS candidates, count(*) AS output_rows,
       count(*) - count(DISTINCT (contract_id, client_id, month_start)) AS duplicate_output_keys,
       coalesce(sum(visit_rows), 0) AS qualified_visit_rows,
       count(*) FILTER (WHERE month_start <> DATE '2026-04-01' OR month_end <> DATE '2026-05-01')
           AS formula_boundary_errors,
       count(*) FILTER (WHERE last_visit IS NOT NULL
                         AND (last_visit < month_start OR last_visit >= month_end)) AS outside_interval,
       count(*) FILTER (WHERE visit_rows >= 4) AS four_plus_rows
FROM agg;

-- NM-V09: the current service filter must retain an orphan-safe join.
SELECT count(*) AS events,
       count(*) FILTER (WHERE n._idrref IS NULL) AS service_orphans,
       count(*) FILTER (WHERE a._fld7579rref IS NULL) AS null_service
FROM public._accumrg7575 a
LEFT JOIN public._reference163 n ON n._idrref = a._fld7579rref
WHERE a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01';

-- NM-V10: raw physical cardinality of the current СПТ client/date match;
-- this does not add or remove any current state filter.
WITH state_day AS MATERIALIZED (
    SELECT _fld7008rref AS client_id, _period::date AS d, count(*) AS n
    FROM public._inforg7006
    WHERE _period >= DATE '2026-01-01' AND _period < DATE '2026-02-01'
    GROUP BY 1,2
), visit_day AS MATERIALIZED (
    SELECT _fld7576rref AS client_id, _period::date AS d, count(*) AS n
    FROM public._accumrg7575
    WHERE _period >= DATE '2026-01-01' AND _period < DATE '2026-02-01'
    GROUP BY 1,2
), matched AS (
    SELECT s.n AS state_events, v.n AS visit_events
    FROM state_day s JOIN visit_day v USING (client_id, d)
)
SELECT (SELECT count(*) FROM state_day) AS state_client_days,
       (SELECT count(*) FROM visit_day) AS visit_client_days,
       count(*) AS matched_client_days, coalesce(sum(state_events), 0) AS matched_state_events,
       coalesce(sum(visit_events), 0) AS matched_visit_events,
       coalesce(sum(state_events * visit_events), 0) AS raw_pair_rows,
       coalesce(max(state_events), 0) AS max_state_events_per_matched_day,
       coalesce(max(visit_events), 0) AS max_visit_events_per_matched_day
FROM matched;
