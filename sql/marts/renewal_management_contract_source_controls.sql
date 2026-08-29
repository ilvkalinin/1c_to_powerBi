-- Independent source controls for mart.renewal_management_contract.
-- $1/$2 are the current-M end-date horizon, inclusive/exclusive.
-- This path deliberately aggregates controls rather than reusing the target extract.

WITH cohort AS MATERIALIZED (
  SELECT a._idrref AS contract_id,a._fld681rref AS client_ref,a._fld671::date AS start_date,
         a._fld672::date AS end_date
  FROM public._reference59 a
  JOIN public._reference141x1 c ON c._idrref=a._fld681rref
  LEFT JOIN public._document332 d332 ON d332._fld4422rref=a._idrref AND d332._posted
  LEFT JOIN public._document287 d287 ON d287._fld3379rref=a._idrref
  WHERE a._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex')
    AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe','hex'),decode('9bd3ea4748457ee94b2011de6d9687d7','hex'))
    AND a._fld672>=$1::date AND a._fld672<$2::date
    AND a._fld693>=30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
    AND extract(day FROM a._fld672-a._fld671)>=30 AND c._code IS NOT NULL
    AND a._fld690=TIMESTAMP '0001-01-01 00:00:00' AND d332._idrref IS NULL AND d287._idrref IS NULL
), price_control AS MATERIALIZED (
  SELECT p._fld7741rref AS contract_id,sum(p._fld7749)::numeric AS purchase_price
  FROM public._accumrg7739 p JOIN cohort c ON c.contract_id=p._fld7741rref
  WHERE p._period>DATE '2015-01-01' AND p._recordkind=0 GROUP BY p._fld7741rref
), visit_control AS MATERIALIZED (
  SELECT c.contract_id,count(*)::bigint AS visit_count
  FROM cohort c JOIN public._accumrg7575 v ON v._fld7578_rrref=c.contract_id
  JOIN public._document325 d ON d._idrref=v._recorderrref
  JOIN public._reference132 club ON club._idrref=v._fld7577rref
  JOIN public._reference141x1 client ON client._idrref=d._fld4171rref
  WHERE d._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex')
    AND club._description NOT IN ('Детский развивающий центр','Управляющая компания')
    AND v._period>=DATE '2026-01-01' AND v._period<DATE '2027-01-01'
    AND client._fld1532rref=decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1','hex')
  GROUP BY c.contract_id
), renewal_control AS MATERIALIZED (
  SELECT c.contract_id,n.activation_date,n.is_free,n.term_days
  FROM cohort c
  LEFT JOIN LATERAL (
    SELECT n._fld670::date AS activation_date,
           n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex') AS is_free,
           n._fld693::numeric AS term_days
    FROM public._reference59 n
    WHERE n._fld681rref=c.client_ref AND n._fld671>c.start_date AND n._fld672>c.end_date
      AND n._fld672>n._fld671 AND n._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex')
      AND n._fld699rref<>decode('9bd3ea4748457ee94b2011de6d9687d7','hex')
      AND ((n._fld693>=30 AND n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex'))
           OR (n._fld693>=1 AND n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex')))
      AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
    ORDER BY n._fld671,(n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex')) DESC,n._idrref
    LIMIT 1
  ) n ON TRUE
)
SELECT count(*)::bigint AS expected_rows,
       count(DISTINCT c.contract_id)::bigint AS expected_distinct_contracts,
       min(c.end_date) AS expected_min_end_date,
       max(c.end_date) AS expected_max_end_date,
       coalesce(sum(p.purchase_price),0)::numeric AS expected_purchase_price,
       coalesce(sum(v.visit_count),0)::bigint AS expected_visit_count,
       count(*) FILTER (WHERE r.activation_date IS NOT NULL)::bigint AS expected_renewed_count,
       count(*) FILTER (WHERE r.activation_date<=date_trunc('month',c.end_date)+interval '1 month')::bigint
           AS expected_renewed_by_month_close_count,
       count(*) FILTER (WHERE r.activation_date<=current_date)::bigint AS expected_renewed_current_count,
       count(*) FILTER (WHERE r.activation_date IS NOT NULL AND NOT r.is_free)::bigint AS expected_paid_renewed_count
FROM cohort c
FULL JOIN price_control p ON p.contract_id=c.contract_id
FULL JOIN visit_control v ON v.contract_id=c.contract_id
FULL JOIN renewal_control r ON r.contract_id=c.contract_id;
