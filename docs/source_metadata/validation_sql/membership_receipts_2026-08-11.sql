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

-- MR-V04 / MB-V-recorder. Expected: every 2026 contract-advance movement is
-- recognised by at most one of the 14 document recorder relations listed in
-- the current PBIT. This validates technical classification coverage only;
-- the current M precedence and its sign/exclusion CASE are not changed.
WITH movements AS MATERIALIZED (
  SELECT _recorderrref AS recorder_id
  FROM public._accumrg7370
  WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
),
recognition AS (
  SELECT m.recorder_id,
         ((d317._idrref IS NOT NULL)::int + (d316._idrref IS NOT NULL)::int +
          (d332._idrref IS NOT NULL)::int + (d285._idrref IS NOT NULL)::int +
          (d304._idrref IS NOT NULL)::int + (d346._idrref IS NOT NULL)::int +
          (d327._idrref IS NOT NULL)::int + (d315._idrref IS NOT NULL)::int +
          (d331._idrref IS NOT NULL)::int + (d305._idrref IS NOT NULL)::int +
          (d333._idrref IS NOT NULL)::int + (d339._idrref IS NOT NULL)::int +
          (d340._idrref IS NOT NULL)::int + (d296._idrref IS NOT NULL)::int)
            AS matching_document_types
  FROM movements m
  LEFT JOIN public._document317 d317 ON d317._idrref = m.recorder_id
  LEFT JOIN public._document316 d316 ON d316._idrref = m.recorder_id
  LEFT JOIN public._document332 d332 ON d332._idrref = m.recorder_id
  LEFT JOIN public._document285 d285 ON d285._idrref = m.recorder_id
  LEFT JOIN public._document304 d304 ON d304._idrref = m.recorder_id
  LEFT JOIN public._document346 d346 ON d346._idrref = m.recorder_id
  LEFT JOIN public._document327 d327 ON d327._idrref = m.recorder_id
  LEFT JOIN public._document315 d315 ON d315._idrref = m.recorder_id
  LEFT JOIN public._document331 d331 ON d331._idrref = m.recorder_id
  LEFT JOIN public._document305 d305 ON d305._idrref = m.recorder_id
  LEFT JOIN public._document333 d333 ON d333._idrref = m.recorder_id
  LEFT JOIN public._document339 d339 ON d339._idrref = m.recorder_id
  LEFT JOIN public._document340 d340 ON d340._idrref = m.recorder_id
  LEFT JOIN public._document296 d296 ON d296._idrref = m.recorder_id
)
SELECT count(*) AS movement_rows,
       count(*) FILTER (WHERE matching_document_types = 1)
         AS exactly_one_recorder_type,
       count(*) FILTER (WHERE matching_document_types = 0)
         AS unrecognised_recorder_rows,
       count(*) FILTER (WHERE matching_document_types > 1)
         AS multiple_recorder_type_rows
FROM recognition;
