-- SV-081. Read-only source validation for «Управление продлением».
-- Run every statement inside BEGIN TRANSACTION READ ONLY with statement_timeout=30000.
-- No query returns client, contract or other operational identifiers.
--
-- RM-V01 expected: all listed relations and fields exist; Reference59 primary key
-- makes contract_id unique. This is a physical-source control, independent of the
-- report's DAX distinct-count measure.
SELECT c.relname, c.relkind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = ANY (ARRAY[
    '_reference59','_reference141x1','_reference163','_reference132',
    '_document287','_document332','_accumrg7739','_accumrg7575',
    '_document325','_inforg6861','_inforg5654','_reference67',
    '_reference106','_reference89','_reference201','_reference202',
    '_reference224','_reference264'
  ])
ORDER BY c.relname;

-- RM-V02 expected: _reference59 has one physical row per _idrref.  Code is a
-- display/integration value, so duplicate-code groups are observed, not treated
-- as a key failure.  Interval and marked counts are observations for the legacy
-- filters, which currently do not filter _marked.
SELECT count(*) AS contract_rows,
       count(DISTINCT _idrref) AS distinct_contract_ids,
       count(*) - count(DISTINCT _idrref) AS duplicate_id_rows,
       count(*) FILTER (WHERE _fld672 <= _fld671) AS nonpositive_intervals,
       count(*) FILTER (WHERE _marked) AS marked_rows,
       (SELECT count(*) FROM (
          SELECT _code FROM public._reference59
          WHERE _code IS NOT NULL AND _code <> ''
          GROUP BY _code HAVING count(*) > 1
       ) d) AS duplicate_code_groups
FROM public._reference59
WHERE _fld672 >= DATE '2024-01-01';

-- RM-V03 expected: the exact current cohort joins do not multiply a contract;
-- i.e. source_rows = distinct_contracts and duplicate_contract_groups = 0.
-- Document287 intentionally has no state predicate here because the current
-- Power Query has none; its state distribution is documented separately.
WITH cohort AS MATERIALIZED (
  SELECT a._idrref AS contract_id
  FROM public._reference59 a
  LEFT JOIN public._reference141x1 cl ON cl._idrref = a._fld681rref
  LEFT JOIN public._document332 d332
    ON d332._fld4422rref = a._idrref AND d332._posted = true
  LEFT JOIN public._document287 d287 ON d287._fld3379rref = a._idrref
  WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2','hex')
    AND a._fld699rref NOT IN (
      decode('96976725cebf51f7461429d74d3f6cbe','hex'),
      decode('9bd3ea4748457ee94b2011de6d9687d7','hex')
    )
    AND a._fld672 > DATE '2024-01-01'
    AND a._fld672 <= date_trunc('month', current_date) + interval '6 month' - interval '1 day'
    AND a._fld693 >= 30
    AND a._description NOT LIKE '%ИП%'
    AND a._description NOT LIKE '%сотрудн%'
    AND extract(day FROM (a._fld672 - a._fld671)) >= 30
    AND cl._code IS NOT NULL
    AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00'
    AND d332._idrref IS NULL
    AND d287._idrref IS NULL
), multiplicity AS (
  SELECT contract_id, count(*) AS n FROM cohort GROUP BY contract_id
)
SELECT (SELECT count(*) FROM cohort) AS source_rows,
       count(*) AS distinct_contracts,
       count(*) FILTER (WHERE n > 1) AS duplicate_contract_groups,
       coalesce(sum(n) FILTER (WHERE n > 1), 0) AS rows_in_duplicate_groups,
       coalesce(max(n), 0) AS max_contract_multiplicity
FROM multiplicity;

-- RM-V04 expected: no earliest-next-start ties in the bounded exact candidate
-- set.  A non-zero result proves the current ORDER BY start LIMIT 1 is
-- non-deterministic; it does not change the legacy selection under BR-018.
WITH base AS MATERIALIZED (
  SELECT a._idrref AS contract_id, a._fld681rref AS client_id,
         a._fld671 AS start_at, a._fld672 AS end_at
  FROM public._reference59 a
  LEFT JOIN public._reference141x1 cl ON cl._idrref = a._fld681rref
  LEFT JOIN public._document332 d332
    ON d332._fld4422rref = a._idrref AND d332._posted = true
  LEFT JOIN public._document287 d287 ON d287._fld3379rref = a._idrref
  WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2','hex')
    AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe','hex'),decode('9bd3ea4748457ee94b2011de6d9687d7','hex'))
    AND a._fld672 > DATE '2024-01-01'
    AND a._fld672 <= date_trunc('month', current_date) + interval '6 month' - interval '1 day'
    AND a._fld693 >= 30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
    AND extract(day FROM (a._fld672 - a._fld671)) >= 30 AND cl._code IS NOT NULL
    AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00' AND d332._idrref IS NULL AND d287._idrref IS NULL
  ORDER BY a._idrref LIMIT 100
), next_candidates AS MATERIALIZED (
  SELECT b.contract_id, n._idrref AS next_contract_id, n._fld671 AS next_start
  FROM base b JOIN public._reference59 n ON n._fld681rref = b.client_id
  WHERE n._fld671 > b.start_at AND n._fld672 > b.end_at AND n._fld672 > n._fld671
    AND n._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2','hex')
    AND n._fld699rref <> decode('9bd3ea4748457ee94b2011de6d9687d7','hex')
    AND ((n._fld693 >= 30 AND n._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe','hex'))
      OR (n._fld693 >= 1 AND n._fld699rref = decode('96976725cebf51f7461429d74d3f6cbe','hex')))
    AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
), min_start AS (
  SELECT contract_id, min(next_start) AS next_start FROM next_candidates GROUP BY contract_id
), ties AS (
  SELECT n.contract_id, count(*) AS n
  FROM next_candidates n JOIN min_start m USING (contract_id, next_start)
  GROUP BY n.contract_id
)
SELECT (SELECT count(*) FROM base) AS sampled_cohorts,
       count(*) AS cohorts_with_next_contract,
       count(*) FILTER (WHERE n > 1) AS earliest_start_tie_groups,
       coalesce(sum(n) FILTER (WHERE n > 1), 0) AS candidate_rows_in_ties,
       coalesce(max(n), 0) AS max_earliest_start_tie
FROM ties;

-- RM-V05 expected: each latest-period join for tenure/rating has one source row
-- per client.  Non-zero ties are a join-multiplication risk for the current PBI
-- 1:1 model.  No business rating/status rule is inferred.
WITH rating_max AS (
  SELECT _fld6862rref AS client_id, max(_period) AS max_period
  FROM public._inforg6861 WHERE _fld6862rref IS NOT NULL GROUP BY 1
), rating_ties AS (
  SELECT r._fld6862rref, r._period, count(*) AS n
  FROM public._inforg6861 r JOIN rating_max m
    ON m.client_id = r._fld6862rref AND m.max_period = r._period
  GROUP BY 1,2 HAVING count(*) > 1
), tenure_max AS (
  SELECT _fld5655rref AS client_id, max(_period) AS max_period
  FROM public._inforg5654 WHERE _fld5655rref IS NOT NULL GROUP BY 1
), tenure_ties AS (
  SELECT t._fld5655rref, t._period, count(*) AS n
  FROM public._inforg5654 t JOIN tenure_max m
    ON m.client_id = t._fld5655rref AND m.max_period = t._period
  GROUP BY 1,2 HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM rating_ties) AS rating_latest_tie_groups,
       (SELECT coalesce(max(n),0) FROM rating_ties) AS rating_max_tie,
       (SELECT count(*) FROM tenure_ties) AS tenure_latest_tie_groups,
       (SELECT coalesce(max(n),0) FROM tenure_ties) AS tenure_max_tie;

-- RM-V06 expected: the legacy price path has one source row per physical
-- register key and at most one matched contract; inactive/record-kind values are
-- observations, not a reason to alter the current WHERE RecordKind = 0 rule.
SELECT count(*) AS price_rows,
       count(DISTINCT (p._recordertref,p._recorderrref,p._lineno)) AS technical_keys,
       count(*) FILTER (WHERE NOT p._active) AS inactive_rows,
       count(*) FILTER (WHERE c._idrref IS NULL) AS contract_orphans,
       count(*) FILTER (WHERE p._recordkind = 0) AS recordkind_0_rows,
       count(*) FILTER (WHERE p._recordkind = 1) AS recordkind_1_rows
FROM public._accumrg7739 p
LEFT JOIN public._reference59 c ON c._idrref = p._fld7741rref
WHERE p._period > DATE '2015-01-01';

-- RM-V07 expected: on the bounded current-PBI visit path, raw count equals
-- distinct technical register keys.  Document count and resource sum are
-- deliberately reported as competing units; BR-018 keeps legacy COUNT(*) until
-- a separately approved methodological change.
WITH contracts AS MATERIALIZED (
  SELECT _idrref, _code
  FROM public._reference59
  WHERE _fld672 > DATE '2024-01-01'
    AND _fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2','hex')
  ORDER BY _idrref LIMIT 100
), visits AS (
  SELECT a._recordertref, a._recorderrref, a._lineno, a._fld7585
  FROM public._accumrg7575 a
  JOIN public._reference59 r ON r._idrref = a._fld7578_rrref
  JOIN contracts c ON c._code = r._code
  JOIN public._document325 d ON d._idrref = a._recorderrref
  JOIN public._reference132 club ON club._idrref = a._fld7577rref
  JOIN public._reference141x1 client ON client._idrref = d._fld4171rref
  WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex')
    AND club._description NOT IN ('Детский развивающий центр','Управляющая компания')
    AND a._period >= DATE '2026-01-01' AND a._period < DATE '2027-01-01'
    AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1','hex')
)
SELECT count(*) AS legacy_count_rows,
       count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS technical_keys,
       count(DISTINCT _recorderrref) AS distinct_visit_documents,
       sum(_fld7585) AS quantity_sum
FROM visits;

-- Execution profile, 2026-08-11: the source role enforces a timeout before the
-- preceding full-scan controls return.  The following bounded source-side
-- controls are the executed Stage 2 evidence; they retain exact legacy filters
-- and report their scope explicitly.  They do not claim full-population proof.

-- RM-V03B expected: each retained current-cohort contract appears once after
-- both legacy exclusion joins.  Scope: first 100 physical contract IDs that
-- satisfy every non-document cohort predicate.
WITH base AS MATERIALIZED (
  SELECT a._idrref AS contract_id
  FROM public._reference59 a
  JOIN public._reference141x1 cl ON cl._idrref = a._fld681rref
  WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2','hex')
    AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe','hex'),decode('9bd3ea4748457ee94b2011de6d9687d7','hex'))
    AND a._fld672 > DATE '2024-01-01'
    AND a._fld672 <= date_trunc('month', current_date) + interval '6 month' - interval '1 day'
    AND a._fld693 >= 30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
    AND extract(day FROM (a._fld672 - a._fld671)) >= 30 AND cl._code IS NOT NULL
    AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00'
  ORDER BY a._idrref LIMIT 100
), retained AS (
  SELECT b.contract_id
  FROM base b LEFT JOIN public._document332 d332 ON d332._fld4422rref=b.contract_id AND d332._posted
              LEFT JOIN public._document287 d287 ON d287._fld3379rref=b.contract_id
  WHERE d332._idrref IS NULL AND d287._idrref IS NULL
), g AS (SELECT contract_id,count(*) n FROM retained GROUP BY 1)
SELECT (SELECT count(*) FROM base) AS sampled_pre_exclusion_contracts,
       (SELECT count(*) FROM retained) AS legacy_retained_rows,
       count(*) AS distinct_retained_contracts,
       count(*) FILTER (WHERE n>1) AS duplicate_contract_groups,
       coalesce(max(n),0) AS max_multiplicity
FROM g;

-- RM-V04B expected: earliest_start_tie_groups = 0.  Scope: the retained
-- contracts from RM-V03B; a tie proves non-deterministic legacy LIMIT 1.
WITH base AS MATERIALIZED (
  SELECT a._idrref contract_id,a._fld681rref client_id,a._fld671 start_at,a._fld672 end_at
  FROM public._reference59 a JOIN public._reference141x1 cl ON cl._idrref=a._fld681rref
  WHERE a._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex')
    AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe','hex'),decode('9bd3ea4748457ee94b2011de6d9687d7','hex'))
    AND a._fld672>DATE '2024-01-01' AND a._fld672<=date_trunc('month',current_date)+interval '6 month'-interval '1 day'
    AND a._fld693>=30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
    AND extract(day FROM (a._fld672-a._fld671))>=30 AND cl._code IS NOT NULL AND a._fld690=TIMESTAMP '0001-01-01 00:00:00'
  ORDER BY a._idrref LIMIT 100
), candidates AS MATERIALIZED (
  SELECT b.contract_id,n._idrref next_contract_id,n._fld671 next_start
  FROM base b JOIN public._reference59 n ON n._fld681rref=b.client_id
  WHERE n._fld671>b.start_at AND n._fld672>b.end_at AND n._fld672>n._fld671
    AND n._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex') AND n._fld699rref<>decode('9bd3ea4748457ee94b2011de6d9687d7','hex')
    AND ((n._fld693>=30 AND n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex')) OR (n._fld693>=1 AND n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex')))
    AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
), first_start AS (SELECT contract_id,min(next_start) next_start FROM candidates GROUP BY 1), ties AS (
  SELECT c.contract_id,count(*) n FROM candidates c JOIN first_start f USING(contract_id,next_start) GROUP BY 1
)
SELECT (SELECT count(*) FROM base) AS sampled_cohorts,count(*) AS cohorts_with_next_contract,
       count(*) FILTER(WHERE n>1) AS earliest_start_tie_groups,
       coalesce(sum(n) FILTER(WHERE n>1),0) AS candidate_rows_in_ties,coalesce(max(n),0) AS max_tie
FROM ties;

-- RM-V05B expected: no ties at the selected client's latest rating or tenure
-- period. Scope: clients of the first 100 filtered contracts; only current PBI
-- latest-period joins are tested.
WITH clients AS MATERIALIZED (
  SELECT DISTINCT a._fld681rref client_id FROM public._reference59 a
  WHERE a._fld672>DATE '2024-01-01' AND a._fld681rref IS NOT NULL ORDER BY 1 LIMIT 100
), rating_max AS (
  SELECT r._fld6862rref client_id,max(r._period) max_period FROM public._inforg6861 r JOIN clients c ON c.client_id=r._fld6862rref GROUP BY 1
), rating_ties AS (
  SELECT r._fld6862rref,count(*) n FROM public._inforg6861 r JOIN rating_max m ON m.client_id=r._fld6862rref AND m.max_period=r._period GROUP BY 1 HAVING count(*)>1
), tenure_max AS (
  SELECT t._fld5655rref client_id,max(t._period) max_period FROM public._inforg5654 t JOIN clients c ON c.client_id=t._fld5655rref GROUP BY 1
), tenure_ties AS (
  SELECT t._fld5655rref,count(*) n FROM public._inforg5654 t JOIN tenure_max m ON m.client_id=t._fld5655rref AND m.max_period=t._period GROUP BY 1 HAVING count(*)>1
)
SELECT (SELECT count(*) FROM clients) AS sampled_clients,
       (SELECT count(*) FROM rating_ties) AS rating_latest_tie_groups,
       (SELECT coalesce(max(n),0) FROM rating_ties) AS rating_max_tie,
       (SELECT count(*) FROM tenure_ties) AS tenure_latest_tie_groups,
       (SELECT coalesce(max(n),0) FROM tenure_ties) AS tenure_max_tie;

-- RM-V06B expected: price rows preserve the physical register key and join to
-- at most one contract. Scope: first 100 contracts of RM-V03B; inactive rows
-- and record-kind frequencies are observations because legacy M filters only
-- RecordKind = 0.
WITH contracts AS MATERIALIZED (
  SELECT a._idrref contract_id FROM public._reference59 a
  WHERE a._fld672>DATE '2024-01-01' ORDER BY a._idrref LIMIT 100
)
SELECT count(*) AS price_rows,
       count(DISTINCT (p._recordertref,p._recorderrref,p._lineno)) AS technical_keys,
       count(*) FILTER(WHERE NOT p._active) AS inactive_rows,
       count(*) FILTER(WHERE p._recordkind=0) AS recordkind_0_rows,
       count(*) FILTER(WHERE p._recordkind=1) AS recordkind_1_rows,
       count(*) FILTER(WHERE r._idrref IS NULL) AS contract_orphans
FROM public._accumrg7739 p JOIN contracts c ON c.contract_id=p._fld7741rref
LEFT JOIN public._reference59 r ON r._idrref=p._fld7741rref
WHERE p._period>DATE '2015-01-01';

-- RM-V07B expected: legacy COUNT(*) equals the number of physical register
-- keys on the current-PBI path. Scope: 100 fixed contract IDs; document count
-- and resource sum are competing units retained as observations under BR-018.
WITH contracts AS MATERIALIZED (
  SELECT _idrref FROM public._reference59 WHERE _fld672>DATE '2024-01-01' ORDER BY _idrref LIMIT 100
), visits AS (
  SELECT a._recordertref,a._recorderrref,a._lineno,a._fld7585
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
       sum(_fld7585) AS quantity_sum
FROM visits;
