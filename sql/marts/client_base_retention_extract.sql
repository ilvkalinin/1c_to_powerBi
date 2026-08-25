-- Source-side aggregate for mart.client_base_retention. Bind $1/$2 to BR-003.
-- BR-037/BR-038 are applied before every baseline/current dedupe and semi-join.
WITH params AS (SELECT $1::date AS horizon_start, $2::date AS horizon_end),
report_dates AS MATERIALIZED (
  SELECT d::date AS report_date FROM params p,
       generate_series(p.horizon_start,p.horizon_end-1,interval '1 day') d
  WHERE extract(isodow FROM d)=1 OR extract(day FROM d)=1
), comparisons AS MATERIALIZED (
  SELECT d.report_date,'year_start'::text AS comparison_type,
         make_date(extract(year FROM d.report_date)::int,1,1) AS comparison_date
  FROM report_dates d
  UNION ALL
  SELECT d.report_date,'previous_year'::text,d.report_date - interval '1 year'
  FROM report_dates d WHERE extract(day FROM d.report_date)=1
    AND d.report_date - interval '1 year' >= (SELECT horizon_start FROM params)
  UNION ALL
  SELECT d.report_date,'previous_year'::text,p.report_date
  FROM report_dates d
  JOIN LATERAL (
    SELECT x.report_date FROM report_dates x
    WHERE extract(isodow FROM d.report_date)=1 AND extract(isodow FROM x.report_date)=1
      AND x.report_date < d.report_date
    ORDER BY abs(x.report_date - (d.report_date - interval '1 year')::date),x.report_date DESC LIMIT 1
  ) p ON true
  WHERE extract(isodow FROM d.report_date)=1
), control_dates AS MATERIALIZED (
  SELECT report_date FROM comparisons UNION SELECT comparison_date::date FROM comparisons
), membership_raw AS MATERIALIZED (
  SELECT ab._fld681rref client_id,ab._fld687rref club_ref,ab._fld671::date active_from,ab._fld672::date active_to
  FROM public._reference59 ab JOIN public._reference141x1 cl ON cl._idrref=ab._fld681rref
  JOIN public._reference132 club ON club._idrref=ab._fld687rref CROSS JOIN params p
  WHERE ab._fld672>=p.horizon_start-1 AND ab._fld671<p.horizon_end AND ab._fld672>ab._fld671
    AND ab._description::varchar NOT ILIKE '%сотруд%' AND ab._description::varchar NOT ILIKE '%ип%'
    AND club._description::varchar<>'Детский развивающий центр'
    AND encode(ab._fld694rref,'hex') IN ('bc06e4b21430ebfb44a67a65c46d41f9','9e369ac955bf602149e17b549b0f1498','91e4594e35ce15d847c4a3f32e1e18f2')
), child_raw AS MATERIALIZED (
  SELECT v._document346_idrref receipt_ref,r._idrref contract_ref,child._idrref client_id,r._fld687rref club_ref,
         adult._idrref adult_ref,stock._fld4932rref product_ref,greatest(r._fld671::date,d._date_time::date) candidate_start,r._fld672::date active_to
  FROM public._document346_vt4913 v JOIN public._document346 d ON d._idrref=v._document346_idrref
  JOIN public._reference59 r ON r._idrref=v._fld4915rref JOIN public._reference141x1 child ON child._idrref=v._fld4916rref
  JOIN public._reference141x1 adult ON adult._idrref=r._fld681rref JOIN public._reference132 club ON club._idrref=r._fld687rref
  LEFT JOIN public._document346_vt4924 stock ON stock._document346_idrref=d._idrref AND stock._fld4929=v._fld4917
  CROSS JOIN params p WHERE d._fld4910rref=decode('859cb45b51f9e02c4fb16764c804af3d','hex')
    AND r._fld672>r._fld671 AND (r._fld670 IS NOT NULL OR r._fld670<>timestamp '0001-01-01')
    AND r._fld681rref IS NOT NULL AND child._code IS NOT NULL AND club._description IS NOT NULL
    AND r._description::varchar NOT ILIKE '%сотруд%' AND r._description::varchar NOT ILIKE '%ип%'
    AND club._description::varchar<>'Детский развивающий центр' AND r._fld672>=p.horizon_start-1
), child_sales AS MATERIALIZED (
  SELECT a._fld7647_rrref receipt_ref,a._fld7648rref adult_ref,a._fld7649rref product_ref,
         sum(a._fld7657)::numeric net_quantity,sum(a._fld7659)::numeric net_amount
  FROM public._accumrg7646 a JOIN (SELECT DISTINCT receipt_ref,adult_ref,product_ref FROM child_raw WHERE product_ref IS NOT NULL) k
    ON (k.receipt_ref,k.adult_ref,k.product_ref)=(a._fld7647_rrref,a._fld7648rref,a._fld7649rref)
  GROUP BY 1,2,3
), child_contracts AS MATERIALIZED (
  SELECT c.contract_ref,c.client_id,c.club_ref,max(c.candidate_start)::date active_from,max(c.active_to)::date active_to
  FROM child_raw c LEFT JOIN child_sales s USING(receipt_ref,adult_ref,product_ref)
  WHERE s.net_quantity IS NULL OR (s.net_quantity>0 AND s.net_amount>0) GROUP BY 1,2,3
), club_candidates AS MATERIALIZED (
  SELECT d.report_date,m.client_id,m.club_ref,false is_child FROM control_dates d JOIN membership_raw m ON m.active_from<d.report_date AND m.active_to>=d.report_date-1
  UNION ALL SELECT d.report_date,c.client_id,c.club_ref,true FROM control_dates d JOIN child_contracts c ON c.active_from<d.report_date AND c.active_to>=d.report_date-1
), club_scope AS MATERIALIZED (
  SELECT DISTINCT ON(report_date,club_ref,client_id) report_date,club_ref,client_id,is_child FROM club_candidates ORDER BY report_date,club_ref,client_id,is_child DESC
), network_scope AS MATERIALIZED (
  SELECT DISTINCT ON(report_date,client_id) report_date,client_id,is_child FROM club_scope ORDER BY report_date,client_id,is_child DESC
), baseline AS MATERIALIZED (
  SELECT c.report_date,c.comparison_type,c.comparison_date::date,'club'::text scope_level,b.club_ref baseline_club_ref,b.client_id FROM comparisons c JOIN club_scope b ON b.report_date=c.comparison_date
  UNION ALL SELECT c.report_date,c.comparison_type,c.comparison_date::date,'network',NULL::bytea,b.client_id FROM comparisons c JOIN network_scope b ON b.report_date=c.comparison_date
), baseline_client_dates AS MATERIALIZED (
  SELECT DISTINCT report_date,client_id FROM baseline
), client_static AS MATERIALIZED (
  SELECT u.report_date,u.client_id,cl._fld1507::date birth_date,
    CASE encode(cl._fld1527rref,'hex') WHEN 'b64a5b1e2f68583046c1077a96a54ebd' THEN 'Женский' WHEN 'b26004420b2465b8457ffa23c30a12aa' THEN 'Мужской' ELSE 'Не указано' END gender,
    coalesce(t.membership_tenure,'Не указано') membership_tenure
  FROM baseline_client_dates u JOIN public._reference141x1 cl ON cl._idrref=u.client_id
  LEFT JOIN LATERAL (SELECT CASE h._fld5656rref WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9','hex') THEN 'New' WHEN decode('9e369ac955bf602149e17b549b0f1498','hex') THEN 'Ex' WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2','hex') THEN 'Renew' ELSE 'Не указано' END::text membership_tenure FROM public._inforg5654 h WHERE h._fld5655rref=u.client_id AND h._period<u.report_date::timestamp ORDER BY h._period DESC,h._fld5656rref LIMIT 1) t ON true
), classified AS (
  SELECT b.*,s.birth_date,s.gender,s.membership_tenure,coalesce(n.is_child,false) current_is_child,n.client_id retained_client
  FROM baseline b JOIN client_static s USING(report_date,client_id) LEFT JOIN network_scope n ON n.report_date=b.report_date AND n.client_id=b.client_id
)
SELECT scope_level,report_date,comparison_type,comparison_date,encode(baseline_club_ref,'hex')::text baseline_club_id,
  CASE WHEN birth_date IS NULL OR birth_date=date '0001-01-01' THEN NULL::smallint ELSE extract(year FROM age(report_date,birth_date))::smallint END current_age_years,
  CASE WHEN current_is_child THEN 'Дети' WHEN birth_date IS NULL OR birth_date=date '0001-01-01' THEN 'Не указано' WHEN extract(year FROM age(report_date,birth_date))<14 THEN 'Дети' WHEN extract(year FROM age(report_date,birth_date))<18 THEN 'Юниоры' ELSE 'Взрослые' END current_age_group,
  gender current_gender,membership_tenure current_membership_tenure,
  count(*)::bigint baseline_client_count,count(retained_client)::bigint retained_client_count
FROM classified
GROUP BY scope_level,report_date,comparison_type,comparison_date,baseline_club_ref,birth_date,gender,membership_tenure,current_is_child;
