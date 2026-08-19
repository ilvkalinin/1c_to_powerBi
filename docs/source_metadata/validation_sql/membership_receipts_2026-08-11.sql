-- SV-083. Read-only bounded source validation for «Отчёт по поступлениям».
-- Execute in BEGIN TRANSACTION READ ONLY. No Excel plan/source is accessed.

-- MR-V01 expected: the two source registers and contract table exist; the
-- register technical keys are physically unique. This does not interpret the
-- RecordKind values as business sign.
SELECT c.relname,c.relkind
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname=ANY(ARRAY['_accumrg7370','_accumrg7739','_reference59','_reference134'])
ORDER BY 1;

-- MR-V11A: archival broad form of the structural input to current DAX quantity.
-- NOT EXECUTED: it did not return within the 30-second source-control limit.
-- MR-V11B—D below preserve its scope in independently executable components.
-- Recurring keeps every contract × payment_period; prepayment must not split
-- into several periods.
WITH current_advances AS (
  SELECT a._fld7371rref AS contract_id,
         regexp_replace(analytics._description::text, '^.*; ', '') AS payment_period,
         CASE WHEN c._fld699rref IS NULL THEN 'Услуга'
              WHEN c._fld699rref = decode('9bd3ea4748457ee94b2011de6d9687d7','hex') THEN 'Рекарринг'
              ELSE 'Предоплата' END AS payment_type,
         (c._fld672::date - c._fld671::date) AS duration_days
  FROM public._accumrg7370 a
  JOIN public._reference59 c ON c._idrref = a._fld7371rref
  JOIN public._reference134 analytics ON analytics._idrref = a._fld7376rref
  JOIN public._enum495 contract_type ON contract_type._idrref = c._fld696rref
  LEFT JOIN public._document317 d317 ON d317._idrref = a._recorderrref
  LEFT JOIN public._document316 d316 ON d316._idrref = a._recorderrref
  LEFT JOIN public._document332 d332 ON d332._idrref = a._recorderrref
  LEFT JOIN public._document285 d285 ON d285._idrref = a._recorderrref
  LEFT JOIN public._document304 d304 ON d304._idrref = a._recorderrref
  LEFT JOIN public._document346 d346 ON d346._idrref = a._recorderrref
  LEFT JOIN public._document327 d327 ON d327._idrref = a._recorderrref
  LEFT JOIN public._document315 d315 ON d315._idrref = a._recorderrref
  LEFT JOIN public._document331 d331 ON d331._idrref = a._recorderrref
  LEFT JOIN public._document305 d305 ON d305._idrref = a._recorderrref
  LEFT JOIN public._document333 d333 ON d333._idrref = a._recorderrref
  LEFT JOIN public._document339 d339 ON d339._idrref = a._recorderrref
  LEFT JOIN public._document340 d340 ON d340._idrref = a._recorderrref
  LEFT JOIN public._document296 d296 ON d296._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01'
    AND contract_type._enumorder <> 0
    AND c._description::text NOT LIKE '%ИП%'
    AND analytics._description::text NOT LIKE '%ДСУ%'
    AND d332._idrref IS NULL
    AND (d317._idrref IS NOT NULL OR d316._idrref IS NOT NULL OR d285._idrref IS NOT NULL
      OR d304._idrref IS NOT NULL OR d346._idrref IS NOT NULL OR d327._idrref IS NOT NULL
      OR d315._idrref IS NOT NULL OR d331._idrref IS NOT NULL OR d305._idrref IS NOT NULL
      OR d333._idrref IS NOT NULL OR d339._idrref IS NOT NULL OR d340._idrref IS NOT NULL
      OR d296._idrref IS NOT NULL)
), units AS (
  SELECT contract_id, payment_period, payment_type, max(duration_days) AS duration_days,
         count(*) AS movement_rows
  FROM current_advances
  GROUP BY 1, 2, 3
), prepayment_contracts AS (
  SELECT contract_id, count(*) AS payment_periods
  FROM units WHERE payment_type = 'Предоплата'
  GROUP BY 1
)
SELECT 'kpi_unit'::text AS metric, payment_type AS value,
       count(*) FILTER (WHERE duration_days > 28) AS duration_eligible_units,
       count(*) FILTER (WHERE duration_days <= 28 OR duration_days IS NULL) AS duration_ineligible_units
FROM units
GROUP BY 1, 2
UNION ALL
SELECT 'prepayment_contract',
       CASE WHEN payment_periods = 1 THEN 'one_payment_period' ELSE 'multiple_payment_periods' END,
       count(*), 0
FROM prepayment_contracts
GROUP BY 1, 2
ORDER BY metric, value;

-- MR-V11B: recurring-only, index-friendly component of MR-V11A.  Recorder
-- exclusivity was already proven by MR-V04, so EXISTS preserves the current
-- recognised/non-sale selection without the broad document joins.
WITH recurring_units AS (
  SELECT a._fld7371rref AS contract_id,
         regexp_replace(analytics._description::text, '^.*; ', '') AS payment_period,
         max(c._fld672::date - c._fld671::date) AS duration_days,
         count(*) AS movement_rows
  FROM public._accumrg7370 a
  JOIN public._reference59 c ON c._idrref = a._fld7371rref
  JOIN public._reference134 analytics ON analytics._idrref = a._fld7376rref
  JOIN public._enum495 contract_type ON contract_type._idrref = c._fld696rref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01'
    AND c._fld699rref = decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
    AND contract_type._enumorder <> 0
    AND c._description::text NOT LIKE '%ИП%'
    AND analytics._description::text NOT LIKE '%ДСУ%'
    AND NOT EXISTS (SELECT 1 FROM public._document332 d WHERE d._idrref = a._recorderrref)
    AND (EXISTS (SELECT 1 FROM public._document317 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document316 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document285 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document304 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document346 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document327 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document315 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document331 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document305 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document333 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document339 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document340 d WHERE d._idrref = a._recorderrref)
      OR EXISTS (SELECT 1 FROM public._document296 d WHERE d._idrref = a._recorderrref))
  GROUP BY 1, 2
)
SELECT count(*) AS recurring_kpi_units,
       count(*) FILTER (WHERE duration_days > 28) AS duration_eligible_units,
       count(*) FILTER (WHERE duration_days <= 28 OR duration_days IS NULL) AS duration_ineligible_units,
       count(*) FILTER (WHERE movement_rows > 1) AS multi_movement_units,
       coalesce(sum(movement_rows - 1) FILTER (WHERE movement_rows > 1), 0) AS movement_row_excess
FROM recurring_units;

-- MR-V11C: prepayment component. The DAX KPI counts one contract, never a
-- payment-period row; measure whether source periods could split a contract.
-- MR-V11D proves that these 13 accepted RecorderTRef values map completely
-- to the same current-M document types (Document332/Sale is deliberately
-- absent). This preserves the exact current-M recognised/non-sale condition
-- while avoiding fourteen repeated document lookups for each movement.
-- Expected before execution: one aggregate row. It observes source structure;
-- no independent Power BI total exists for reconciliation in this control.
WITH prepayment_rows AS (
  SELECT a._fld7371rref AS contract_id,
         regexp_replace(analytics._description::text, '^.*; ', '') AS payment_period,
         c._fld672::date - c._fld671::date AS duration_days
  FROM public._accumrg7370 a
  JOIN public._reference59 c ON c._idrref = a._fld7371rref
  JOIN public._reference134 analytics ON analytics._idrref = a._fld7376rref
  JOIN public._enum495 contract_type ON contract_type._idrref = c._fld696rref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01'
    AND a._recordertref = ANY(ARRAY[
      decode('0000013d','hex'), decode('0000013c','hex'), decode('0000011d','hex'),
      decode('00000130','hex'), decode('0000015a','hex'), decode('00000147','hex'),
      decode('0000013b','hex'), decode('0000014b','hex'), decode('00000131','hex'),
      decode('0000014d','hex'), decode('00000153','hex'), decode('00000154','hex'),
      decode('00000128','hex')])
    AND c._fld699rref IS NOT NULL
    AND c._fld699rref <> decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
    AND contract_type._enumorder <> 0
    AND (c._description IS NULL OR c._description::text NOT LIKE '%ИП%')
    AND analytics._description::text NOT LIKE '%ДСУ%'
), per_contract AS (
  SELECT contract_id, max(duration_days) AS duration_days,
         count(DISTINCT payment_period) AS payment_periods,
         count(*) AS movement_rows
  FROM prepayment_rows
  GROUP BY 1
)
SELECT count(*) AS prepayment_contracts,
       count(*) FILTER (WHERE duration_days > 28) AS duration_eligible_contracts,
       count(*) FILTER (WHERE duration_days <= 28 OR duration_days IS NULL) AS duration_ineligible_contracts,
       count(*) FILTER (WHERE payment_periods > 1) AS contracts_with_multiple_payment_periods,
       coalesce(sum(payment_periods - 1) FILTER (WHERE payment_periods > 1), 0) AS payment_period_excess,
       count(*) FILTER (WHERE movement_rows > 1) AS multi_movement_contracts
FROM per_contract;

-- MR-V11D: physical proof for the RecorderTRef optimisation in MR-V11C.
-- Expected before execution: every typed row maps to its current-M document;
-- unmatched_rows = 0. Document285 may have no rows in the bounded period.
WITH checks AS (
  SELECT 'Document317'::text AS document_name, count(*) AS typed_rows, count(d._idrref) AS matched_rows
  FROM public._accumrg7370 a LEFT JOIN public._document317 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000013d','hex')
  UNION ALL SELECT 'Document316', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document316 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000013c','hex')
  UNION ALL SELECT 'Document332', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document332 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000014c','hex')
  UNION ALL SELECT 'Document285', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document285 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000011d','hex')
  UNION ALL SELECT 'Document304', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document304 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('00000130','hex')
  UNION ALL SELECT 'Document346', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document346 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000015a','hex')
  UNION ALL SELECT 'Document327', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document327 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('00000147','hex')
  UNION ALL SELECT 'Document315', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document315 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000013b','hex')
  UNION ALL SELECT 'Document331', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document331 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000014b','hex')
  UNION ALL SELECT 'Document305', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document305 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('00000131','hex')
  UNION ALL SELECT 'Document333', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document333 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('0000014d','hex')
  UNION ALL SELECT 'Document339', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document339 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('00000153','hex')
  UNION ALL SELECT 'Document340', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document340 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('00000154','hex')
  UNION ALL SELECT 'Document296', count(*), count(d._idrref)
  FROM public._accumrg7370 a LEFT JOIN public._document296 d ON d._idrref = a._recorderrref
  WHERE a._period >= TIMESTAMP '2025-01-01' AND a._period < TIMESTAMP '2027-01-01' AND a._recordertref = decode('00000128','hex')
)
SELECT document_name, typed_rows, matched_rows, typed_rows - matched_rows AS unmatched_rows
FROM checks
ORDER BY document_name;

-- MR-V11E: exact current-M grouping before the DAX net-amount condition.
-- Expected: one result row per payment type; the previously validated
-- contract+day co-access key must not multiply an advance group.
WITH raw_advances AS (
  SELECT a._period::date AS event_date, a._fld7371rref AS contract_id,
         x._description::text AS analytics_text,
         CASE WHEN c._fld699rref = decode('9bd3ea4748457ee94b2011de6d9687d7','hex') THEN 'recurring'
              WHEN c._fld699rref = decode('96976725cebf51f7461429d74d3f6cbe','hex') THEN 'free'
              WHEN c._fld699rref = decode('9a96b207e6e963c44a4421511fef04e5','hex') THEN 'credit' ELSE 'prepayment' END AS payment_type,
         c._fld681rref AS client_id, c._fld687rref AS access_club_id, c._fld701rref AS sales_point_club_id,
         c._fld670::date AS activation_date, c._fld671::date AS start_date, c._fld672::date AS end_date,
         c._fld694rref AS source_stage_id, p._description::text AS product_name, p._fld1756 AS freeze_days,
         p._idrref AS product_id, c._fld693 AS term_days, c._fld668rref AS purchase_type_id,
         c._fld667rref AS membership_kind_id, c._fld697rref AS club_access_type_id,
         CASE WHEN d327._fld4235rref IS NOT NULL AND d327._fld4235rref <> decode('00000000000000000000000000000000','hex') THEN 'instalment'
              ELSE CASE coalesce(d304._fld3680rref,d346._fld4891rref,d305._fld3712rref,d339._fld4702rref,d331._fld4395rref)
                WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f','hex') THEN 'club' WHEN decode('99ad9b75dc73f34911eed62832d12269','hex') THEN 'website'
                WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d','hex') THEN 'app' WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e','hex') THEN 'employee_app'
                WHEN decode('99aff84c6229c6ae11eef6b58cf54f81','hex') THEN 'web_customer' END END AS source_object,
         CASE WHEN a._recordkind=1 AND a._recordertref=ANY(ARRAY[decode('0000013c','hex'),decode('0000014d','hex'),decode('00000154','hex'),decode('0000013b','hex'),decode('00000130','hex')]) THEN -a._fld7377
              WHEN a._recordkind=1 AND a._recordertref=decode('0000014b','hex') THEN 0 ELSE a._fld7377 END AS signed_amount
  FROM public._accumrg7370 a JOIN public._reference59 c ON c._idrref=a._fld7371rref JOIN public._reference163 p ON p._idrref=c._fld685rref JOIN public._reference134 x ON x._idrref=a._fld7376rref JOIN public._enum495 e ON e._idrref=c._fld696rref
  LEFT JOIN public._document304 d304 ON d304._idrref=a._recorderrref LEFT JOIN public._document346 d346 ON d346._idrref=a._recorderrref LEFT JOIN public._document327 d327 ON d327._idrref=a._recorderrref LEFT JOIN public._document305 d305 ON d305._idrref=a._recorderrref LEFT JOIN public._document339 d339 ON d339._idrref=a._recorderrref LEFT JOIN public._document331 d331 ON d331._idrref=a._recorderrref
  WHERE a._period>=DATE '2025-01-01' AND a._period<DATE '2027-01-01' AND a._recordertref=ANY(ARRAY[decode('0000013d','hex'),decode('0000013c','hex'),decode('0000011d','hex'),decode('00000130','hex'),decode('0000015a','hex'),decode('00000147','hex'),decode('0000013b','hex'),decode('0000014b','hex'),decode('00000131','hex'),decode('0000014d','hex'),decode('00000153','hex'),decode('00000154','hex'),decode('00000128','hex')]) AND c._fld699rref IS NOT NULL AND e._enumorder<>0 AND (c._description IS NULL OR c._description::text NOT LIKE '%ИП%') AND x._description::text NOT LIKE '%ДСУ%'
), m_groups AS (
  SELECT event_date,contract_id,analytics_text,payment_type,client_id,access_club_id,sales_point_club_id,activation_date,start_date,end_date,source_stage_id,product_name,freeze_days,product_id,term_days,purchase_type_id,membership_kind_id,club_access_type_id,source_object,sum(signed_amount) gross_amount
  FROM raw_advances GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
), co_access AS (
  SELECT a._period::date AS event_date,a._fld7741rref AS contract_id,sum(a._fld7749) amount
  FROM public._accumrg7739 a JOIN public._reference163 p ON p._idrref=a._fld7743rref JOIN public._reference59 c ON c._idrref=a._fld7741rref
  WHERE a._period>=DATE '2025-01-01' AND a._period<DATE '2027-01-01' AND a._fld7743rref<>decode('00000000000000000000000000000000','hex') AND a._recordkind=1 AND (p._description::text LIKE '%Со-д%' OR p._description::text LIKE '%со-д%') AND c._fld687rref IS NOT NULL GROUP BY 1,2
), contract_period AS (
  SELECT m.contract_id,regexp_replace(m.analytics_text,'^.*; ','') payment_period,m.payment_type,sum(m.gross_amount-coalesce(c.amount,0)) net_amount
  FROM m_groups m LEFT JOIN co_access c USING(event_date,contract_id) GROUP BY 1,2,3
)
SELECT payment_type,count(*) contract_periods,count(*) FILTER(WHERE net_amount=0) zero_net_contract_periods,count(*) FILTER(WHERE net_amount<>0) nonzero_net_contract_periods
FROM contract_period GROUP BY 1 ORDER BY 1;

-- MR-V11F: current-M co-access grouping must stay unique by contract + date.
-- Expected on BR-003: current_m_grouped_rows = contract_day_keys and both
-- multiplicity measures equal zero.  This is a cardinality control only.
WITH current_m_groups AS (
  SELECT a._period::date AS event_date,a._fld7741rref AS contract_id,
         a._fld7744rref AS counterparty_id,c._fld687rref AS access_club_id,
         p._description::text AS product_name,sum(a._fld7749) amount
  FROM public._accumrg7739 a
  JOIN public._reference163 p ON p._idrref=a._fld7743rref
  JOIN public._reference59 c ON c._idrref=a._fld7741rref
  WHERE a._period>=DATE '2025-01-01' AND a._period<DATE '2027-01-01'
    AND a._fld7743rref<>decode('00000000000000000000000000000000','hex')
    AND a._recordkind=1
    AND (p._description::text LIKE '%Со-д%' OR p._description::text LIKE '%со-д%')
    AND c._fld687rref IS NOT NULL
  GROUP BY 1,2,3,4,5
), per_key AS (
  SELECT event_date,contract_id,count(*) grouped_rows,sum(amount) amount
  FROM current_m_groups GROUP BY 1,2
)
SELECT (SELECT count(*) FROM current_m_groups) current_m_grouped_rows,
       count(*) contract_day_keys,
       count(*) FILTER (WHERE grouped_rows>1) keys_with_multiple_m_groups,
       coalesce(sum(grouped_rows-1) FILTER (WHERE grouped_rows>1),0) excess_m_groups,
       sum(amount) co_access_amount
FROM per_key;

-- MR-V10C: current-PBIT channel, access-zone and access-type coverage on the
-- contract-advance branch. This retains the recorder precedence and text
-- conditions; it only counts current DAX output categories.
WITH movements AS (
  SELECT a._recorderrref AS recorder_id, a._lineno AS line_no,
         a._fld7371rref AS contract_id, a._fld7372rref AS movement_club_id,
         a._fld7376rref AS analytics_id
  FROM public._accumrg7370 a
  WHERE a._period >= TIMESTAMP '2025-01-01'
    AND a._period < TIMESTAMP '2027-01-01'
), classified AS (
  SELECT m.recorder_id, m.line_no, c._description::text AS contract_name,
         p._description::text AS product_name, club._description::text AS movement_club_name,
         c._fld697rref AS club_access_type_id, analytics._description::text AS analytics_name,
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
           WHEN d327._fld4235rref IS NOT NULL
            AND d327._fld4235rref <> decode('00000000000000000000000000000000', 'hex') THEN 'Рассрочка'
           ELSE coalesce(
             CASE d332._fld4433rref
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f', 'hex') THEN 'Клуб'
               WHEN decode('99ad9b75dc73f34911eed62832d12269', 'hex') THEN 'Website'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d', 'hex') THEN 'App'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e', 'hex') THEN 'App сотрудника'
               WHEN decode('99aff84c6229c6ae11eef6b58cf54f81', 'hex') THEN 'Web customer'
             END,
             CASE d304._fld3680rref
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f', 'hex') THEN 'Клуб'
               WHEN decode('99ad9b75dc73f34911eed62832d12269', 'hex') THEN 'Website'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d', 'hex') THEN 'App'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e', 'hex') THEN 'App сотрудника'
               WHEN decode('99aff84c6229c6ae11eef6b58cf54f81', 'hex') THEN 'Web customer'
             END,
             CASE d346._fld4891rref
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f', 'hex') THEN 'Клуб'
               WHEN decode('99ad9b75dc73f34911eed62832d12269', 'hex') THEN 'Website'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d', 'hex') THEN 'App'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e', 'hex') THEN 'App сотрудника'
               WHEN decode('99aff84c6229c6ae11eef6b58cf54f81', 'hex') THEN 'Web customer'
             END,
             CASE d305._fld3712rref
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f', 'hex') THEN 'Клуб'
               WHEN decode('99ad9b75dc73f34911eed62832d12269', 'hex') THEN 'Website'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d', 'hex') THEN 'App'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e', 'hex') THEN 'App сотрудника'
               WHEN decode('99aff84c6229c6ae11eef6b58cf54f81', 'hex') THEN 'Web customer'
             END,
             CASE d339._fld4702rref
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f', 'hex') THEN 'Клуб'
               WHEN decode('99ad9b75dc73f34911eed62832d12269', 'hex') THEN 'Website'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d', 'hex') THEN 'App'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e', 'hex') THEN 'App сотрудника'
               WHEN decode('99aff84c6229c6ae11eef6b58cf54f81', 'hex') THEN 'Web customer'
             END,
             CASE d331._fld4395rref
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f', 'hex') THEN 'Клуб'
               WHEN decode('99ad9b75dc73f34911eed62832d12269', 'hex') THEN 'Website'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d', 'hex') THEN 'App'
               WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e', 'hex') THEN 'App сотрудника'
               WHEN decode('99aff84c6229c6ae11eef6b58cf54f81', 'hex') THEN 'Web customer'
             END
           )
         END AS source_channel
  FROM movements m
  LEFT JOIN public._reference59 c ON c._idrref = m.contract_id
  LEFT JOIN public._reference163 p ON p._idrref = c._fld685rref
  LEFT JOIN public._reference132 club ON club._idrref = m.movement_club_id
  LEFT JOIN public._reference134 analytics ON analytics._idrref = m.analytics_id
  LEFT JOIN public._enum495 contract_type ON contract_type._idrref = c._fld696rref
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
  WHERE contract_type._enumorder <> 0
    AND (c._description IS NULL OR c._description::text NOT LIKE '%ИП%')
    AND (analytics._description IS NULL OR analytics._description::text NOT LIKE '%ДСУ%')
), current_dax AS (
  SELECT *,
         CASE WHEN product_name ILIKE '%web%' THEN 'Web customer'
              WHEN source_channel IS NOT NULL AND source_channel <> '' THEN source_channel
              ELSE 'Клуб' END AS payment_source_current,
         CASE WHEN movement_club_name = 'Пушкинский VIP' THEN
              CASE WHEN product_name ILIKE '%кандидат%' THEN 'VIP кандидат'
                   WHEN product_name ILIKE '%Exclusive 2%' OR product_name ILIKE '%Exclusive II%' THEN 'Exclusive II'
                   WHEN product_name ILIKE '%Exclusive%' THEN 'Exclusive'
                   ELSE 'VIP' END
              ELSE 'Весь клуб' END AS access_zone_current,
         CASE WHEN product_name ILIKE '%сеть%' THEN 'Сетевой'
              WHEN club_access_type_id = decode('abf82ac2a7cb5ed04be0f28e6fe07689', 'hex') THEN 'Сетевой'
              WHEN club_access_type_id = decode('ac64dcb94a278ff64f8f05b6aa470169', 'hex') THEN 'Локальный'
              ELSE 'Отсутствует' END AS club_access_type_current
  FROM classified
  WHERE recorder_type IS NOT NULL AND recorder_type <> 'sale'
)
SELECT classification, current_value, count(*) AS movement_rows
FROM (
  SELECT 'payment_source'::text AS classification, payment_source_current AS current_value FROM current_dax
  UNION ALL SELECT 'access_zone', access_zone_current FROM current_dax
  UNION ALL SELECT 'club_access_type', club_access_type_current FROM current_dax
) x
GROUP BY 1, 2
ORDER BY 1, 2;

-- MR-V10D: measure the exact PBIT InfoRg8595 Table.Distinct(product) risk.
-- The control never picks a row: it only counts conflicting access-time values.
WITH pbit_index_rows AS (
  SELECT DISTINCT i._fld8603rref AS product_id,
         payment._description::text AS payment_type,
         access_time._description::text AS access_time,
         age._description::text AS product_age,
         duration._description::text AS duration_type,
         quantity_limit._description::text AS quantity_limit_type,
         coupon._description::text AS coupon_type,
         product._description::text AS product_name
  FROM public._inforg8595 i
  LEFT JOIN public._reference109 payment ON payment._idrref = i._fld8597rref
  LEFT JOIN public._reference109 age ON age._idrref = i._fld8598rref
  LEFT JOIN public._reference109 access_time ON access_time._idrref = i._fld8599rref
  LEFT JOIN public._reference109 duration ON duration._idrref = i._fld8600rref
  LEFT JOIN public._reference109 quantity_limit ON quantity_limit._idrref = i._fld8601rref
  LEFT JOIN public._reference109 coupon ON coupon._idrref = i._fld8602rref
  LEFT JOIN public._reference163 product ON product._idrref = i._fld8603rref
  WHERE payment._description IS NOT NULL
), current_contract_products AS (
  SELECT DISTINCT c._fld685rref AS product_id
  FROM public._reference59 c
  WHERE c._fld670 >= TIMESTAMP '2025-01-01'
    AND c._fld670 < TIMESTAMP '2027-01-01'
    AND c._fld681rref <> decode('00000000000000000000000000000000', 'hex')
    AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
    AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
    AND c._description::text NOT LIKE '%ИП%'
    AND c._description::text NOT LIKE '%клип%'
    AND c._description::text NOT LIKE '%Клип%'
), per_product AS (
  SELECT product_id, count(*) AS pbit_rows,
         count(DISTINCT access_time) AS access_time_values
  FROM pbit_index_rows
  GROUP BY 1
)
SELECT scope,
       count(*) AS products,
       count(*) FILTER (WHERE pbit_rows > 1) AS products_with_multiple_pbit_rows,
       coalesce(sum(pbit_rows - 1) FILTER (WHERE pbit_rows > 1), 0) AS pbit_row_excess,
       count(*) FILTER (WHERE access_time_values > 1) AS products_with_conflicting_access_time
FROM (
  SELECT 'all_current_pbit_index'::text AS scope, p.* FROM per_product p
  UNION ALL
  SELECT 'current_contract_products'::text, p.*
  FROM per_product p JOIN current_contract_products c ON c.product_id = p.product_id
) scoped
GROUP BY scope
ORDER BY scope;

-- MR-V10E: exact DAX coverage for access-time output after the confirmed
-- unique InfoRg8595 product lookup. Text "дневн" keeps current priority.
WITH pbit_index AS (
  SELECT DISTINCT i._fld8603rref AS product_id,
         access_time._description::text AS access_time
  FROM public._inforg8595 i
  LEFT JOIN public._reference109 payment ON payment._idrref = i._fld8597rref
  LEFT JOIN public._reference109 access_time ON access_time._idrref = i._fld8599rref
  WHERE payment._description IS NOT NULL
), current_pbit_contracts AS (
  SELECT c._idrref AS contract_id, c._fld685rref AS product_id,
         p._description::text AS product_name
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
)
SELECT CASE
         WHEN c.product_name ILIKE '%дневн%' THEN 'Дневной Физкульт'
         WHEN i.access_time IS NOT NULL AND i.access_time <> '' THEN i.access_time
         ELSE 'Безлимитный'
       END AS access_time_current,
       count(*) AS contracts,
       count(*) FILTER (WHERE i.product_id IS NULL) AS contracts_without_index_row
FROM current_pbit_contracts c
LEFT JOIN pbit_index i ON i.product_id = c.product_id
GROUP BY 1
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
