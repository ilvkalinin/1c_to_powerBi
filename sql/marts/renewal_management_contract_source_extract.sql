-- REVIEWED Stage-3 source extract for mart.renewal_management_contract; no target operation.
-- Reproduces current M predicates plus BR-050 deterministic ties.
WITH cohort AS MATERIALIZED (
  SELECT a._idrref contract_id,a._code::text contract_code,a._fld681rref client_ref,a._fld671::date start_date,a._fld672::date end_date,a._fld693::numeric term_days,a._fld687rref club_ref
  FROM public._reference59 a JOIN public._reference141x1 c ON c._idrref=a._fld681rref
  LEFT JOIN public._document332 d332 ON d332._fld4422rref=a._idrref AND d332._posted
  LEFT JOIN public._document287 d287 ON d287._fld3379rref=a._idrref
  WHERE a._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex')
    AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe','hex'),decode('9bd3ea4748457ee94b2011de6d9687d7','hex'))
    AND a._fld672>=$1::date AND a._fld672<$2::date
    AND a._fld693>=30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
    AND extract(day FROM a._fld672-a._fld671)>=30 AND c._code IS NOT NULL AND a._fld690=TIMESTAMP '0001-01-01 00:00:00'
    AND d332._idrref IS NULL AND d287._idrref IS NULL
), cohort_clients AS MATERIALIZED (
  SELECT DISTINCT client_ref FROM cohort
), prices AS MATERIALIZED (
  SELECT p._fld7741rref contract_id,sum(p._fld7749)::numeric purchase_price FROM public._accumrg7739 p
  JOIN cohort c ON c.contract_id=p._fld7741rref
  WHERE p._period>DATE '2015-01-01' AND p._recordkind=0 GROUP BY p._fld7741rref
), visits AS MATERIALIZED (
  SELECT c.contract_id,count(*)::bigint visit_count FROM public._accumrg7575 v
  JOIN cohort c ON c.contract_id=v._fld7578_rrref JOIN public._document325 d ON d._idrref=v._recorderrref
  JOIN public._reference132 club ON club._idrref=v._fld7577rref JOIN public._reference141x1 client ON client._idrref=d._fld4171rref
  WHERE d._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex') AND club._description NOT IN ('Детский развивающий центр','Управляющая компания')
    AND v._period>=DATE '2026-01-01' AND v._period<DATE '2027-01-01' AND client._fld1532rref=decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1','hex')
  GROUP BY c.contract_id
), rating AS MATERIALIZED (
  SELECT DISTINCT ON (r._fld6862rref) r._fld6862rref client_ref,CASE encode(r._fld6863rref,'hex')
   WHEN '00000000000000000000000000000000' THEN 'Без рейтинга' WHEN 'b791f8238f1e0a07497e01ff5e6b3532' THEN 'Базовый' WHEN 'b7fa39fc5ea14fd944082fbb2e478d08' THEN 'Бронзовый' WHEN '81393529f530e03347f3d3af2ad0c881' THEN 'Серебряный' WHEN 'a3a43b03aacf38194d50cd7806f9a1d4' THEN 'Золотой' WHEN 'a86b00b8cfac31254f8290bb111da2fb' THEN 'Черный' END current_rating
  FROM public._inforg6861 r JOIN cohort_clients cc ON cc.client_ref=r._fld6862rref
  ORDER BY r._fld6862rref,r._period DESC
), tenure AS MATERIALIZED (
  SELECT DISTINCT ON (t._fld5655rref) t._fld5655rref client_ref,CASE encode(t._fld5656rref,'hex') WHEN 'bc06e4b21430ebfb44a67a65c46d41f9' THEN 'New' WHEN '91e4594e35ce15d847c4a3f32e1e18f2' THEN 'Renew' WHEN '9e369ac955bf602149e17b549b0f1498' THEN 'Ex' ELSE 'Неизвестный стаж' END current_tenure
  FROM public._inforg5654 t JOIN cohort_clients cc ON cc.client_ref=t._fld5655rref
  ORDER BY t._fld5655rref,t._period DESC
), interaction AS MATERIALIZED (
  SELECT DISTINCT ON (task._fld1196rref) task._fld1196rref client_ref,i._fld820 last_interaction_at,
   CASE encode(i._fld831rref,'hex') WHEN 'b538e5326d9fc9a943c11fd0e7a0e678' THEN 'Встреча' WHEN 'af240c30136a9c4e4c4d477d359e0f03' THEN 'Заявка на обратный звонок' WHEN '8590e885ee4c688946c3e23782968752' THEN 'Входящий звонок' WHEN '8d7225693e34b52f450fe5181ac00cb9' THEN 'Исходящий звонок' WHEN '9db9fdbf6bd80f2044eb2835157b3bc8' THEN 'Обратная связь' WHEN '8b888f0c4a5eb1724b77b72ebeffdf6b' THEN 'Онлайн покупка' WHEN '8cdb19ca805f72d94dfd36278e121b82' THEN 'Отмена гостевого визита' WHEN '8f6da46ad3a0c51b4bb9feb594cb3b9c' THEN 'Оформление' WHEN 'a991e34cdfd2527449f98fb5c998a54d' THEN 'Переход по клику' WHEN '87c74245c038b6244d8f6f7169c0d545' THEN 'Регистрация гостевого визита' WHEN 'b70ab7149b54e8f240c0203b5ae78b63' THEN 'Регистрация рекомендации' WHEN '8d375d1bd8b128d447da1f927d95614c' THEN 'Уведомление' WHEN '952f4279216ec5844b0b165542d2d0d4' THEN 'Чат' WHEN '811e1e78f495bbd940b19032400397a3' THEN 'Входящее письмо' WHEN 'b86111863fbaefeb42b967aaa9ae4ce2' THEN 'Исходящее письмо' ELSE NULL END last_interaction_type,
   stage._description::text current_funnel_stage,reason._description::text current_fail_reason
  FROM public._reference67 i JOIN public._reference106 task ON task._idrref=i._owneridrref JOIN cohort_clients cc ON cc.client_ref=task._fld1196rref JOIN public._reference141x1 client ON client._idrref=task._fld1196rref JOIN public._reference89 typ ON typ._idrref=task._fld1191rref
  LEFT JOIN public._reference264 stage ON stage._idrref=task._fld1205rref LEFT JOIN public._reference201 reason ON reason._idrref=task._fld1201rref LEFT JOIN public._reference202 src ON src._idrref=i._fld828rref LEFT JOIN public._reference224 st ON st._idrref=i._fld829rref
  WHERE i._fld823>=DATE '2023-11-01' AND typ._description='Продажа клубной карты' AND i._fld831rref<>decode('8f6da46ad3a0c51b4bb9feb594cb3b9c','hex') AND st._description IS DISTINCT FROM 'Запланировано' AND src._description IS DISTINCT FROM 'Авто' AND client._code IS NOT NULL AND i._fld820<>TIMESTAMP '0001-01-01 00:00:00'
  ORDER BY task._fld1196rref,i._fld820 DESC,i._idrref
)
SELECT encode(c.contract_id,'hex') AS expiring_contract_id,c.contract_code AS expiring_contract_code,encode(c.client_ref,'hex') AS client_id,client._code::text AS client_code,client._description::text AS client_name,client._fld1531::text AS client_phone,client._fld1507::date AS birth_date,c.start_date AS membership_start_date,c.end_date AS membership_end_date,date_trunc('month',c.end_date)::date AS contract_end_month,c.term_days AS membership_term_days,encode(c.club_ref,'hex') AS access_club_id,p.purchase_price,coalesce(v.visit_count,0)::bigint AS visit_count,
  coalesce(v.visit_count,0)::numeric/nullif(c.term_days,0) usage_rate,coalesce(v.visit_count,0)::numeric/nullif((12*(extract(year FROM c.end_date)-extract(year FROM c.start_date))+extract(month FROM c.end_date)-extract(month FROM c.start_date)+1),0) average_monthly_visits,
  coalesce(n.activation_date<=date_trunc('month',c.end_date)+interval '1 month',false) renewed_by_month_close_flag,coalesce(n.activation_date<=current_date,false) renewed_current_flag,
  encode(n.next_id,'hex') AS next_contract_id,n.next_code AS next_contract_code,n.activation_date AS renewal_activation_date,n.next_start_date AS next_contract_start_date,n.term_days AS next_contract_term_days,
  CASE WHEN n.next_id IS NULL THEN 'Не продлен' WHEN n.is_free AND n.term_days>=90 THEN 'Бесплатное длинное продление' WHEN n.is_free THEN 'Бесплатное короткое продление' ELSE 'Платное продление' END renewal_type,
  (n.activation_date-c.end_date) renewal_lead_lag_days,CASE WHEN n.activation_date>c.end_date THEN n.activation_date-c.end_date END return_days,
  CASE WHEN n.activation_date IS NULL THEN NULL WHEN n.activation_date<=c.end_date THEN 'До окончания' WHEN n.activation_date-c.end_date<=30 THEN '0–30' WHEN n.activation_date-c.end_date<=60 THEN '31–60' WHEN n.activation_date-c.end_date<=90 THEN '61–90' WHEN n.activation_date-c.end_date<=180 THEN '91–180' ELSE '181+' END return_bucket,
  rating.current_rating,tenure.current_tenure,i.last_interaction_at,i.last_interaction_type,i.current_funnel_stage,i.current_fail_reason
FROM cohort c JOIN public._reference141x1 client ON client._idrref=c.client_ref
FULL JOIN prices p ON p.contract_id=c.contract_id
FULL JOIN visits v ON v.contract_id=c.contract_id
FULL JOIN rating ON rating.client_ref=c.client_ref
FULL JOIN tenure ON tenure.client_ref=c.client_ref
FULL JOIN interaction i ON i.client_ref=c.client_ref
LEFT JOIN LATERAL (SELECT n._idrref next_id,n._code::text next_code,n._fld670::date activation_date,n._fld671::date next_start_date,n._fld693::numeric term_days,n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex') is_free FROM public._reference59 n WHERE n._fld681rref=c.client_ref AND n._fld671>c.start_date AND n._fld672>c.end_date AND n._fld672>n._fld671 AND n._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex') AND n._fld699rref<>decode('9bd3ea4748457ee94b2011de6d9687d7','hex') AND ((n._fld693>=30 AND n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex')) OR (n._fld693>=1 AND n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex'))) AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%' ORDER BY n._fld671,(n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex')) DESC,n._idrref LIMIT 1) n ON TRUE;
