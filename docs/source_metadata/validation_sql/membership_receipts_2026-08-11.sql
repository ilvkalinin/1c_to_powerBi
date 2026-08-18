-- SV-083. Read-only bounded source validation for «Отчёт по поступлениям».
-- Execute in BEGIN TRANSACTION READ ONLY. No Excel plan/source is accessed.

-- MR-V01 expected: the two source registers and contract table exist; the
-- register technical keys are physically unique. This does not interpret the
-- RecordKind values as business sign.
SELECT c.relname,c.relkind
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname=ANY(ARRAY['_accumrg7370','_accumrg7739','_reference59','_reference134'])
ORDER BY 1;

-- MR-V02 expected: each bounded advance movement has one physical key and at
-- most one contract join. Active and RecordKind are observations; current M
-- determines sign through its document-recorder CASE and must be preserved.
WITH movements AS MATERIALIZED (
  SELECT _recordertref,_recorderrref,_lineno,_fld7371rref,_active,_recordkind
  FROM public._accumrg7370 WHERE _period>=DATE '2026-01-01' AND _period<DATE '2027-01-01'
  ORDER BY _recordertref,_recorderrref,_lineno LIMIT 100
)
SELECT count(*) AS movement_rows,
       count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS technical_keys,
       count(*) FILTER(WHERE c._idrref IS NULL) AS contract_orphans,
       count(*) FILTER(WHERE NOT m._active) AS inactive_rows,
       count(*) FILTER(WHERE m._recordkind=0) AS recordkind_0_rows,
       count(*) FILTER(WHERE m._recordkind=1) AS recordkind_1_rows
FROM movements m LEFT JOIN public._reference59 c ON c._idrref=m._fld7371rref;

-- MR-V03 expected: each bounded counterparty movement has one physical key and
-- at most one contract join. Legacy service scope and text classification are
-- not recomputed here.
WITH movements AS MATERIALIZED (
  SELECT _recordertref,_recorderrref,_lineno,_fld7741rref,_active,_recordkind
  FROM public._accumrg7739 WHERE _period>=DATE '2026-01-01' AND _period<DATE '2027-01-01'
  ORDER BY _recordertref,_recorderrref,_lineno LIMIT 100
)
SELECT count(*) AS movement_rows,
       count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS technical_keys,
       count(*) FILTER(WHERE c._idrref IS NULL) AS contract_orphans,
       count(*) FILTER(WHERE NOT m._active) AS inactive_rows,
       count(*) FILTER(WHERE m._recordkind=0) AS recordkind_0_rows,
       count(*) FILTER(WHERE m._recordkind=1) AS recordkind_1_rows
FROM movements m LEFT JOIN public._reference59 c ON c._idrref=m._fld7741rref;

-- MR-V03A / MB-V-source-states, executed for the board-reused domain.
-- Expected: observe the complete 2026 combinations of Active and RecordKind
-- separately for contract advances and membership services. It establishes no
-- new state or sign filter: document-recorder sign logic remains current M.
SELECT source_kind, active, record_kind, movement_rows, amount_total
FROM (
  SELECT 'contract_advance'::text AS source_kind,
         _active AS active,
         _recordkind AS record_kind,
         count(*) AS movement_rows,
         sum(_fld7377) AS amount_total
  FROM public._accumrg7370
  WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
  GROUP BY 1, 2, 3

  UNION ALL

  SELECT 'membership_service'::text AS source_kind,
         _active AS active,
         _recordkind AS record_kind,
         count(*) AS movement_rows,
         sum(_fld7749) AS amount_total
  FROM public._accumrg7739
  WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
  GROUP BY 1, 2, 3
) states
ORDER BY source_kind, active, record_kind;
