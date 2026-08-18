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

-- MR-V06A: test the cardinality of the current-PBIT sales-price branch over
-- the agreed BR-003 history.  The predicates and two price fields repeat the
-- PBIT source; only its legacy lower date is replaced by the project horizon.
-- Expected: at most one distinct price pair per contract, or observed ties are
-- preserved for a later explicit tie-break decision.  No Table.Distinct-style
-- arbitrary pick is applied here.
WITH current_pbit_sales AS (
  SELECT a._fld7655rref AS contract_id,
         a._fld7659 AS price_field_7659,
         a._fld7660 AS price_field_7660
  FROM public._accumrg7646 a
  LEFT JOIN public._reference163 p ON p._idrref = a._fld7649rref
  WHERE a._period >= DATE '2025-01-01' AND a._period < DATE '2027-01-01'
    AND a._fld7657 IS NOT NULL AND a._fld7657 = 1
    AND a._fld7655rref <> decode('00000000000000000000000000000000', 'hex')
    AND p._description::text NOT LIKE 'Заморозка%'
    AND p._description::text NOT LIKE 'со-доступ%'
), per_contract AS (
  SELECT contract_id,
         count(*) AS sales_rows,
         count(DISTINCT (price_field_7659, price_field_7660)) AS distinct_price_pairs
  FROM current_pbit_sales
  GROUP BY 1
)
SELECT (SELECT count(*) FROM current_pbit_sales) AS sales_rows,
       count(*) AS contracts,
       count(*) FILTER (WHERE sales_rows > 1) AS contracts_with_multiple_sales_rows,
       coalesce(sum(sales_rows - 1) FILTER (WHERE sales_rows > 1), 0) AS sales_row_excess,
       count(*) FILTER (WHERE distinct_price_pairs > 1) AS contracts_with_multiple_price_pairs
FROM per_contract;

-- MR-V08A: the PBIT predecessor index is assigned after sorting contracts by
-- activation date without a secondary order.  Measure same-client activation
-- ties in the current contract scope; do not invent an ID tie-break.
WITH current_pbit_contracts AS (
  SELECT c._fld681rref AS client_id, c._idrref AS contract_id,
         c._fld670::date AS activation_date
  FROM public._reference59 c
  WHERE c._fld670 >= DATE '2025-01-01' AND c._fld670 < DATE '2027-01-01'
    AND c._fld681rref <> decode('00000000000000000000000000000000', 'hex')
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._description::text NOT LIKE '%ИП%'
    AND c._description::text NOT LIKE '%клип%'
    AND c._description::text NOT LIKE '%Клип%'
), ties AS (
  SELECT client_id, activation_date, count(*) AS contract_rows
  FROM current_pbit_contracts
  GROUP BY 1, 2
  HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM current_pbit_contracts) AS contracts,
       count(*) AS client_activation_ties,
       coalesce(sum(contract_rows - 1), 0) AS tied_contract_excess,
       max(contract_rows) AS max_contracts_per_client_activation
FROM ties;

-- MR-V09A: physical cardinality of the three exact current-PBIT freeze
-- branches.  Horizon follows BR-003; current M adds no source-state filter.
WITH freeze_movements AS (
  SELECT a._recorderrref AS recorder_id, a._lineno AS line_no,
         a._period, a._fld7479rref AS contract_id, a._fld7481 AS freeze_days
  FROM public._accumrg7478 a
  WHERE a._period >= TIMESTAMP '2025-01-01'
    AND a._period < TIMESTAMP '2027-01-01'
    AND a._recordkind = 0
), free_freeze AS (
  SELECT m.*
  FROM freeze_movements m
  JOIN public._document266 d ON d._idrref = m.recorder_id
  JOIN public._reference59 c ON c._idrref = m.contract_id
  WHERE m._period::date BETWEEN c._fld674::date AND c._fld670::date
), paid_freeze_orp AS (
  SELECT m.*
  FROM freeze_movements m
  JOIN public._document315_vt3894 o
    ON o._document315_idrref = m.recorder_id
   AND o._fld3896rref = m.contract_id
  JOIN public._reference59 c ON c._idrref = m.contract_id
  WHERE m._period::date BETWEEN c._fld674::date AND c._fld670::date
), paid_freeze_cash AS (
  SELECT p.*, v._fld4938 AS cash_amount
  FROM paid_freeze_orp p
  JOIN public._document315_vt3894 o
    ON o._document315_idrref = p.recorder_id
   AND o._fld3896rref = p.contract_id
  JOIN public._document346 d ON d._idrref = o._fld3897rref
  JOIN public._document346_vt4924 v ON v._document346_idrref = d._idrref
  JOIN public._reference163 n ON n._idrref = v._fld4932rref
  WHERE d._date_time = p._period
    AND n._fld1756 * v._fld4930 = p.freeze_days
    AND v._fld4938 <> 0
), sold_freeze AS (
  SELECT a._recorderrref AS recorder_id, a._lineno AS line_no,
         a._fld7655rref AS contract_id, a._fld7659 AS sale_amount,
         n._fld1756 AS freeze_days
  FROM public._accumrg7646 a
  JOIN public._document332 d ON d._idrref = a._recorderrref
  JOIN public._reference163 n ON n._idrref = a._fld7649rref
  LEFT JOIN public._reference59 c ON c._idrref = a._fld7655rref
  WHERE a._period >= TIMESTAMP '2025-01-01'
    AND a._period < TIMESTAMP '2027-01-01'
    AND n._fld1795rref = decode('82595a6eb69e532e454747ab1bc61f6a', 'hex')
    AND a._fld7659 <> 0
)
SELECT branch,
       count(*) AS rows_after_current_branch_join,
       count(DISTINCT (recorder_id, line_no)) AS movement_keys,
       count(*) - count(DISTINCT (recorder_id, line_no)) AS join_row_excess,
       sum(days)::numeric(18,2) AS days_sum,
       sum(amount)::numeric(18,2) AS amount_sum
FROM (
  SELECT 'free_activation'::text AS branch, recorder_id, line_no,
         freeze_days AS days, 0::numeric AS amount FROM free_freeze
  UNION ALL
  SELECT 'paid_orp'::text, recorder_id, line_no, freeze_days, 0::numeric
  FROM paid_freeze_orp
  UNION ALL
  SELECT 'paid_cash'::text, recorder_id, line_no, freeze_days, cash_amount
  FROM paid_freeze_cash
  UNION ALL
  SELECT 'sold_with_contract'::text, recorder_id, line_no, freeze_days, sale_amount
  FROM sold_freeze
) x
GROUP BY branch
ORDER BY branch;

-- MR-V10A: exact PBIT contract-level coverage for payment, product age and
-- source stage. Check before price joins so their known multiplicity cannot
-- inflate classification counts.
WITH current_pbit_contracts AS (
  SELECT c._idrref AS contract_id, c._fld699rref AS payment_type_id,
         c._fld696rref AS contract_type_id, c._fld694rref AS source_stage_id,
         p._fld1741rref AS product_age_id, p._description::text AS product_name
  FROM public._reference59 c
  LEFT JOIN public._reference163 p ON p._idrref = c._fld685rref
  WHERE c._fld670 >= TIMESTAMP '2025-01-01'
    AND c._fld670 < TIMESTAMP '2027-01-01'
    AND c._fld681rref <> decode('00000000000000000000000000000000', 'hex')
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._description::text NOT LIKE '%ИП%'
    AND c._description::text NOT LIKE '%клип%'
    AND c._description::text NOT LIKE '%Клип%'
), classified AS (
  SELECT c.*,
         CASE
           WHEN payment_type_id = decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex') THEN 'Рекарринг'
           WHEN payment_type_id = decode('96976725cebf51f7461429d74d3f6cbe', 'hex') THEN 'Бесплатный'
           ELSE 'Предоплата'
         END AS payment_type_current,
         CASE
           WHEN contract_type_id = decode('b3810658562bb24d4270435597b56bd7', 'hex') THEN 'Детские секции'
           WHEN product_name LIKE '%детские секции%' OR product_name LIKE '%Детские секции%'
             OR product_name LIKE '%ДЕТСКИЕ СЕКЦИИ%' THEN 'Детские секции'
           WHEN product_age_id = decode('80d300505681013811e4d84b6c6561d9', 'hex') THEN 'Взрослые'
           WHEN product_age_id = decode('80d300505681013811e4d85d67cfb97d', 'hex') THEN 'Дети'
           WHEN product_age_id = decode('80d300505681013811e4d85d6e92a534', 'hex') THEN 'Юниоры'
           ELSE 'Взрослые'
         END AS product_age_current,
         e._enumorder AS source_stage_order
  FROM current_pbit_contracts c
  LEFT JOIN public._enum402 e ON e._idrref = c.source_stage_id
)
SELECT 'payment_type'::text AS classification, payment_type_current AS current_value,
       count(*) AS contracts
FROM classified
GROUP BY 1, 2
UNION ALL
SELECT 'product_age', product_age_current, count(*)
FROM classified
GROUP BY 1, 2
UNION ALL
SELECT 'source_stage_order',
       CASE WHEN source_stage_order = 0 THEN 'New'
            WHEN source_stage_order = 1 THEN 'Renew'
            WHEN source_stage_order IS NULL THEN 'unmapped_or_null'
            ELSE 'Ex' END,
       count(*)
FROM classified
GROUP BY 1, 2
ORDER BY classification, current_value;

-- MR-V10B: split the source-stage values that do not join the exact PBIT
-- Enum402 mapping. No fallback category is introduced by this control.
WITH current_pbit_contracts AS (
  SELECT c._fld694rref AS source_stage_id
  FROM public._reference59 c
  WHERE c._fld670 >= TIMESTAMP '2025-01-01'
    AND c._fld670 < TIMESTAMP '2027-01-01'
    AND c._fld681rref <> decode('00000000000000000000000000000000', 'hex')
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._description::text NOT LIKE '%ИП%'
    AND c._description::text NOT LIKE '%клип%'
    AND c._description::text NOT LIKE '%Клип%'
)
SELECT CASE
         WHEN source_stage_id = decode('00000000000000000000000000000000', 'hex') THEN 'zero_reference'
         WHEN source_stage_id IS NULL THEN 'null_reference'
         WHEN e._idrref IS NULL THEN 'not_in_enum402'
         WHEN e._enumorder = 0 THEN 'New'
         WHEN e._enumorder = 1 THEN 'Renew'
         ELSE 'Ex'
       END AS current_mapping_path,
       count(*) AS contracts
FROM current_pbit_contracts c
LEFT JOIN public._enum402 e ON e._idrref = c.source_stage_id
GROUP BY 1
ORDER BY 1;

-- MR-V09B: reproduce the Table.Distinct columns of the two PBIT freeze
-- queries.  Compare only within the source query scope, without new filters.
WITH movement AS (
  SELECT a._recorderrref AS recorder_id, a._lineno AS line_no, a._period,
         a._recordkind, a._fld7479rref AS contract_id, a._fld7481 AS freeze_days,
         a._fld644rref AS author_id
  FROM public._accumrg7478 a
  WHERE a._period >= TIMESTAMP '2025-01-01'
    AND a._period < TIMESTAMP '2027-01-01'
    AND a._recordkind = 0
), early_raw AS (
  SELECT m._period, m.line_no, m._recordkind, m.contract_id, m.freeze_days,
         m.author_id, c._fld694rref AS stage_id, sales._description::text AS sales_point,
         c._fld671 AS start_date, c._fld670 AS activation_date, c._fld674 AS acquisition_date,
         source266._description::text AS source_object, c._description::text AS contract_name
  FROM movement m
  JOIN public._document266 d ON d._idrref = m.recorder_id
  LEFT JOIN public._reference59 c ON c._idrref = m.contract_id
  LEFT JOIN public._document332 d332 ON d332._idrref = c._fld677_rrref
  LEFT JOIN public._reference124 source266 ON source266._idrref = d332._fld4433rref
  LEFT JOIN public._reference132 sales ON sales._idrref = c._fld701rref
  UNION ALL
  SELECT m._period, m.line_no, m._recordkind, m.contract_id, m.freeze_days,
         m.author_id, c._fld694rref, sales._description::text,
         c._fld671, c._fld670, c._fld674,
         source315._description::text, c._description::text
  FROM movement m
  JOIN public._document315_vt3894 o
    ON o._document315_idrref = m.recorder_id
   AND o._fld3896rref = m.contract_id
  LEFT JOIN public._reference59 c ON c._idrref = m.contract_id
  LEFT JOIN public._reference132 sales ON sales._idrref = c._fld701rref
  LEFT JOIN public._document346_vt4924 v ON v._document346_idrref = o._fld3897rref
  LEFT JOIN public._document346 d ON d._idrref = o._fld3897rref
  LEFT JOIN public._reference127 r127 ON r127._idrref = d._fld4892rref
  LEFT JOIN public._reference237 source315 ON source315._idrref = r127._fld1357rref
), early_distinct AS (
  SELECT DISTINCT * FROM early_raw
), paid_raw AS (
  SELECT m._period, m.contract_id, m.freeze_days, c._fld671 AS start_date,
         c._fld670 AS activation_date, c._fld674 AS acquisition_date,
         c._description::text AS contract_name, v._fld4938 AS amount,
         v._fld4939 AS automatic_discount
  FROM movement m
  JOIN public._document315_vt3894 o
    ON o._document315_idrref = m.recorder_id
   AND o._fld3896rref = m.contract_id
  LEFT JOIN public._reference59 c ON c._idrref = m.contract_id
  LEFT JOIN public._document346_vt4924 v ON v._document346_idrref = o._fld3897rref
  LEFT JOIN public._document346 d ON d._idrref = o._fld3897rref
  LEFT JOIN public._reference163 n ON n._idrref = v._fld4932rref
  WHERE d._date_time = m._period
    AND n._fld1756 * v._fld4930 = m.freeze_days
), paid_distinct AS (
  SELECT DISTINCT * FROM paid_raw
)
SELECT branch, raw_rows, distinct_rows, raw_days, distinct_days, raw_amount, distinct_amount
FROM (
  SELECT 'early_freeze'::text AS branch,
         (SELECT count(*) FROM early_raw
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date) AS raw_rows,
         (SELECT count(*) FROM early_distinct
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date) AS distinct_rows,
         (SELECT coalesce(sum(freeze_days), 0) FROM early_raw
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date) AS raw_days,
         (SELECT coalesce(sum(freeze_days), 0) FROM early_distinct
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date) AS distinct_days,
         0::numeric AS raw_amount, 0::numeric AS distinct_amount
  UNION ALL
  SELECT 'paid_orp'::text,
         (SELECT count(*) FROM paid_raw
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date AND amount <> 0),
         (SELECT count(*) FROM paid_distinct
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date AND amount <> 0),
         (SELECT coalesce(sum(freeze_days), 0) FROM paid_raw
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date AND amount <> 0),
         (SELECT coalesce(sum(freeze_days), 0) FROM paid_distinct
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date AND amount <> 0),
         (SELECT coalesce(sum(amount), 0) FROM paid_raw
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date AND amount <> 0),
         (SELECT coalesce(sum(amount), 0) FROM paid_distinct
          WHERE _period::date BETWEEN acquisition_date::date AND activation_date::date AND amount <> 0)
) result
ORDER BY branch;
