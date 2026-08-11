-- SV-082. Read-only source validation for «Отчет по %Renew».
-- Execute each statement in BEGIN TRANSACTION READ ONLY.  No Excel file or
-- its Power Query is read; all controls use only the confirmed gymdb sources.

-- RU-V01 expected: the physical fields used by the mapping exist and are
-- non-nullable.  Reference59.ID is the technical key; contract_code is only a
-- current integration key and is checked separately for duplicate groups.
SELECT c.relname,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod) AS physical_type,a.attnotnull
FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname=ANY(ARRAY['_accumrg7575','_reference59','_document325'])
  AND a.attnum>0 AND NOT a.attisdropped
  AND (a.attname LIKE '_fld7578%' OR a.attname IN ('_period','_active','_recordertref','_recorderrref','_lineno','_fld7585','_idrref','_code','_fld671','_fld672','_fld693','_marked','_posted'))
ORDER BY 1,2;

-- RU-V02 expected: on the bounded exact current-PBI path, legacy COUNT(*)
-- equals physical register keys.  Document count and resource quantity are
-- competing units, reported without changing the legacy metric (BR-018).
WITH contracts AS MATERIALIZED (
  SELECT _idrref FROM public._reference59
  WHERE _fld672>DATE '2024-01-01' AND _fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex')
  ORDER BY _idrref LIMIT 100
), visits AS (
  SELECT a._recordertref,a._recorderrref,a._lineno,a._fld7585,a._fld7578_type,a._fld7578_rtref
  FROM public._accumrg7575 a JOIN contracts c ON c._idrref=a._fld7578_rrref
  JOIN public._document325 d ON d._idrref=a._recorderrref
  JOIN public._reference132 club ON club._idrref=a._fld7577rref
  JOIN public._reference141x1 client ON client._idrref=d._fld4171rref
  WHERE d._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex')
    AND club._description NOT IN ('Детский развивающий центр','Управляющая компания')
    AND a._period>=DATE '2026-01-01' AND a._period<DATE '2027-01-01'
    AND client._fld1532rref=decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1','hex')
)
SELECT count(*) AS legacy_count_rows,
       count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS technical_keys,
       count(DISTINCT _recorderrref) AS distinct_visit_documents,
       sum(_fld7585) AS quantity_sum,
       count(DISTINCT (_fld7578_type,_fld7578_rtref)) AS contract_reference_type_pairs
FROM visits;

-- RU-V03 expected: a 2025–2026 crossing-contract sample exposes whether the
-- current fixed 2026 window omits in-interval visits before 2026.  This is an
-- observation, not a replacement for the current M filter.
WITH contracts AS MATERIALIZED (
  SELECT _idrref,_fld671 AS start_at,_fld672 AS end_at FROM public._reference59
  WHERE _fld671<DATE '2026-01-01' AND _fld672>=DATE '2026-01-01' AND _fld672>_fld671
  ORDER BY _idrref LIMIT 100
), visits AS (
  SELECT a._period,a._recordertref,a._recorderrref,a._lineno
  FROM public._accumrg7575 a JOIN contracts c ON c._idrref=a._fld7578_rrref
  JOIN public._document325 d ON d._idrref=a._recorderrref
  JOIN public._reference132 club ON club._idrref=a._fld7577rref
  JOIN public._reference141x1 client ON client._idrref=d._fld4171rref
  WHERE a._period>=c.start_at AND a._period<=c.end_at
    AND d._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex')
    AND club._description NOT IN ('Детский развивающий центр','Управляющая компания')
    AND client._fld1532rref=decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1','hex')
)
SELECT (SELECT count(*) FROM contracts) AS sampled_cross_year_contracts,
       count(*) AS full_interval_rows,
       count(*) FILTER(WHERE _period<DATE '2026-01-01') AS omitted_by_legacy_2026_window,
       count(*) FILTER(WHERE _period>=DATE '2026-01-01') AS retained_by_legacy_2026_window,
       count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS technical_keys
FROM visits;

-- RU-V04 expected: the 100 contract sample has non-null term and dates.  Term
-- is observed against date arithmetic, not equated: freezes/corrections may
-- legitimately create a difference and require no BR-018 change.
WITH sample AS MATERIALIZED (
  SELECT _fld671::date AS start_date,_fld672::date AS end_date,_fld693 AS term_days
  FROM public._reference59 WHERE _fld672>=DATE '2024-01-01' ORDER BY _idrref LIMIT 100
)
SELECT count(*) AS sampled_contracts,
       count(*) FILTER(WHERE term_days IS NULL OR term_days<=0) AS invalid_term_rows,
       count(*) FILTER(WHERE end_date<=start_date) AS nonpositive_interval_rows,
       count(*) FILTER(WHERE term_days<>(end_date-start_date)) AS term_differs_from_calendar_days,
       min(term_days) AS min_term_days,max(term_days) AS max_term_days
FROM sample;
