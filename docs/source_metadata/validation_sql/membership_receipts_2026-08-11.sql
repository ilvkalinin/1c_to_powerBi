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

-- MR-V03B / MB-V-state-sign.  Reproduce the current M precedence, its one
-- excluded type (sale), and its sign CASE for recognised 2026 advances.
-- Expected: every included row has exactly one document type; Posted/Marked
-- remain observations, not new filters.  RecordKind is interpreted only by
-- the preserved CASE: transfer, RKO, cashless write-off, sales report and card
-- are negated at kind 1; PKO is zero at kind 1; all other combinations retain
-- the raw amount.
WITH movements AS MATERIALIZED (
  SELECT _recorderrref AS recorder_id, _recordkind AS record_kind, _fld7377 AS amount_raw
  FROM public._accumrg7370
  WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
), classified AS (
  SELECT m.*,
         CASE
           WHEN d317._idrref IS NOT NULL THEN 'transfer'
           WHEN d316._idrref IS NOT NULL THEN 'transfer_contract'
           WHEN d332._idrref IS NOT NULL THEN 'sale'
           WHEN d285._idrref IS NOT NULL THEN 'return'
           WHEN d304._idrref IS NOT NULL THEN 'card'
           WHEN d346._idrref IS NOT NULL THEN 'cash_receipt'
           WHEN d327._idrref IS NOT NULL THEN 'cashless'
           WHEN d315._idrref IS NOT NULL THEN 'sales_report'
           WHEN d331._idrref IS NOT NULL THEN 'pko'
           WHEN d305._idrref IS NOT NULL THEN 'certificate'
           WHEN d333._idrref IS NOT NULL THEN 'rko'
           WHEN d339._idrref IS NOT NULL THEN 'advance_writeoff'
           WHEN d340._idrref IS NOT NULL THEN 'cashless_writeoff'
           WHEN d296._idrref IS NOT NULL THEN 'recurring_correction'
         END AS recorder_type,
         CASE
           WHEN d317._idrref IS NOT NULL THEN d317._posted
           WHEN d316._idrref IS NOT NULL THEN d316._posted
           WHEN d332._idrref IS NOT NULL THEN d332._posted
           WHEN d285._idrref IS NOT NULL THEN d285._posted
           WHEN d304._idrref IS NOT NULL THEN d304._posted
           WHEN d346._idrref IS NOT NULL THEN d346._posted
           WHEN d327._idrref IS NOT NULL THEN d327._posted
           WHEN d315._idrref IS NOT NULL THEN d315._posted
           WHEN d331._idrref IS NOT NULL THEN d331._posted
           WHEN d305._idrref IS NOT NULL THEN d305._posted
           WHEN d333._idrref IS NOT NULL THEN d333._posted
           WHEN d339._idrref IS NOT NULL THEN d339._posted
           WHEN d340._idrref IS NOT NULL THEN d340._posted
           WHEN d296._idrref IS NOT NULL THEN d296._posted
         END AS recorder_posted,
         CASE
           WHEN d317._idrref IS NOT NULL THEN d317._marked
           WHEN d316._idrref IS NOT NULL THEN d316._marked
           WHEN d332._idrref IS NOT NULL THEN d332._marked
           WHEN d285._idrref IS NOT NULL THEN d285._marked
           WHEN d304._idrref IS NOT NULL THEN d304._marked
           WHEN d346._idrref IS NOT NULL THEN d346._marked
           WHEN d327._idrref IS NOT NULL THEN d327._marked
           WHEN d315._idrref IS NOT NULL THEN d315._marked
           WHEN d331._idrref IS NOT NULL THEN d331._marked
           WHEN d305._idrref IS NOT NULL THEN d305._marked
           WHEN d333._idrref IS NOT NULL THEN d333._marked
           WHEN d339._idrref IS NOT NULL THEN d339._marked
           WHEN d340._idrref IS NOT NULL THEN d340._marked
           WHEN d296._idrref IS NOT NULL THEN d296._marked
         END AS recorder_marked
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
), included AS (
  SELECT *,
         CASE
           WHEN record_kind = 1 AND recorder_type IN (
             'transfer_contract', 'rko', 'cashless_writeoff', 'sales_report', 'card'
           ) THEN -amount_raw
           WHEN record_kind = 1 AND recorder_type = 'pko' THEN 0
           ELSE amount_raw
         END AS amount_signed
  FROM classified
  WHERE recorder_type IS NOT NULL AND recorder_type <> 'sale'
)
SELECT recorder_type, record_kind, recorder_posted, recorder_marked,
       count(*) AS movement_rows,
       round(sum(amount_raw)::numeric, 2) AS amount_raw_total,
       round(sum(amount_signed)::numeric, 2) AS amount_signed_total
FROM included
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;

-- MR-V03C: test whether the current-M zero branch for PKO is physically
-- exercised in the available BR-003 history.  Expected: RecordKind=1 rows,
-- if present, contribute zero.  Their absence preserves the rule but leaves
-- that branch unobserved rather than inferred.
SELECT _recordkind AS record_kind,
       count(*) AS movement_rows,
       round(sum(_fld7377)::numeric, 2) AS amount_raw_total,
       round(sum(CASE WHEN _recordkind = 1 THEN 0 ELSE _fld7377 END)::numeric, 2)
         AS amount_signed_total
FROM public._accumrg7370 a
JOIN public._document331 d ON d._idrref = a._recorderrref
WHERE a._period >= DATE '2025-01-01' AND a._period < DATE '2027-01-01'
GROUP BY 1
ORDER BY 1;

-- MR-V05A: validate that the 14 one-to-one recorder joins themselves do not
-- multiply the 2026 advance register.  The recognised-current-M subset is
-- reported separately: excluding unrecognised rows and sale is a preserved
-- report rule, not a join-preservation failure.
WITH movements AS MATERIALIZED (
  SELECT _recorderrref AS recorder_id, _lineno AS line_no, _fld7377 AS amount_raw
  FROM public._accumrg7370
  WHERE _period >= DATE '2026-01-01' AND _period < DATE '2027-01-01'
), joined AS (
  SELECT m.*,
         CASE
           WHEN d317._idrref IS NOT NULL THEN 'transfer'
           WHEN d316._idrref IS NOT NULL THEN 'transfer_contract'
           WHEN d332._idrref IS NOT NULL THEN 'sale'
           WHEN d285._idrref IS NOT NULL THEN 'return'
           WHEN d304._idrref IS NOT NULL THEN 'card'
           WHEN d346._idrref IS NOT NULL THEN 'cash_receipt'
           WHEN d327._idrref IS NOT NULL THEN 'cashless'
           WHEN d315._idrref IS NOT NULL THEN 'sales_report'
           WHEN d331._idrref IS NOT NULL THEN 'pko'
           WHEN d305._idrref IS NOT NULL THEN 'certificate'
           WHEN d333._idrref IS NOT NULL THEN 'rko'
           WHEN d339._idrref IS NOT NULL THEN 'advance_writeoff'
           WHEN d340._idrref IS NOT NULL THEN 'cashless_writeoff'
           WHEN d296._idrref IS NOT NULL THEN 'recurring_correction'
         END AS recorder_type
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
SELECT (SELECT count(*) FROM movements) AS source_rows,
       count(*) AS joined_rows,
       count(*) - (SELECT count(*) FROM movements) AS join_row_excess,
       round((SELECT sum(amount_raw)::numeric FROM movements), 2) AS source_amount_total,
       round(sum(amount_raw)::numeric, 2) AS joined_amount_total,
       round(sum(amount_raw)::numeric - (SELECT sum(amount_raw)::numeric FROM movements), 2)
         AS join_amount_difference,
       count(*) FILTER (WHERE recorder_type IS NOT NULL AND recorder_type <> 'sale')
         AS current_m_included_rows,
       round(sum(amount_raw) FILTER (WHERE recorder_type IS NOT NULL AND recorder_type <> 'sale')::numeric, 2)
         AS current_m_included_raw_amount
FROM joined;

-- MR-V07A: exact current-PBIT co-access scope and its relationship key.
-- Expected: the PBIT relation uses contract + day.  If the current M grouping
-- leaves multiple rows per that key, a future source-side aggregate is required
-- before the relation; no rows are silently dropped.
WITH current_m_grouped AS (
  SELECT a._period::date AS event_date,
         a._fld7741rref AS contract_id,
         a._fld7744rref AS counterparty_id,
         c._fld687rref AS access_club_id,
         p._description::text AS product_name,
         sum(a._fld7749) AS amount_total
  FROM public._accumrg7739 a
  JOIN public._reference163 p ON p._idrref = a._fld7743rref
  JOIN public._reference59 c ON c._idrref = a._fld7741rref
  WHERE a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01'
    AND a._fld7743rref <> decode('00000000000000000000000000000000', 'hex')
    AND a._recordkind = 1
    AND (p._description::text LIKE '%Со-д%' OR p._description::text LIKE '%со-д%')
    AND c._fld687rref IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5
), per_relationship_key AS (
  SELECT event_date, contract_id, count(*) AS grouped_rows, sum(amount_total) AS amount_total
  FROM current_m_grouped
  GROUP BY 1, 2
)
SELECT (SELECT count(*) FROM current_m_grouped) AS current_m_grouped_rows,
       count(*) AS contract_day_keys,
       count(*) FILTER (WHERE grouped_rows > 1) AS multirow_contract_day_keys,
       coalesce(sum(grouped_rows - 1) FILTER (WHERE grouped_rows > 1), 0) AS relationship_key_excess_rows,
       round(sum(amount_total)::numeric, 2) AS co_access_amount_total
FROM per_relationship_key;
