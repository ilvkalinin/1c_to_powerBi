-- $1 = inclusive BR-003 date; $2 = exclusive BR-003 date.
-- Read-only projection of one client-level visit event. Coupon, DPFU, group
-- lessons and IP are independent current-PBIT facts and are not row flags.
WITH constants AS (
  SELECT decode('9a5a4c90d2b1aede4b91dcd1abe84c43','hex') AS visit_operation,
         decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1','hex') AS client_type,
         decode('89de5e634e304b1a44efac5ab7088373','hex') AS membership_service
), base_visits AS MATERIALIZED (
  SELECT a._period::date AS visit_date,
         d._fld4167rref AS club_ref,
         d._fld4171rref AS client_ref,
         a._fld7578_rrref AS contract_ref,
         a._fld7579rref AS visit_service_ref
  FROM public._accumrg7575 a
  JOIN public._document325 d ON d._idrref=a._recorderrref
  JOIN public._reference141x1 cl ON cl._idrref=d._fld4171rref
  CROSS JOIN constants k
  WHERE a._period >= $1::date AND a._period < $2::date
    AND d._fld4164rref=k.visit_operation
    AND cl._fld1532rref=k.client_type AND cl._code IS NOT NULL
), base_visit_keys AS (
  SELECT visit_date, club_ref, client_ref
  FROM base_visits
  GROUP BY visit_date, club_ref, client_ref
), pushkin_club AS (
  SELECT _idrref AS club_ref
  FROM public._reference132
  WHERE _description::text='Пушкинский'
), pushkin_flags AS (
  SELECT b.visit_date, b.club_ref, b.client_ref,
         coalesce(bool_or(home._description::text='Пушкинский'
                          AND contract_service._fld1795rref=k.membership_service), false) AS has_member_visit,
         coalesce(bool_or((lower(coalesce(visit_service._description::text,'')) LIKE '%гостевой визит%'
                               OR lower(coalesce(visit_service._description::text,'')) LIKE '%гост%')
                          AND lower(coalesce(visit_service._description::text,'')) NOT LIKE '%гость кафе%'), false) AS has_guest_visit,
         coalesce(bool_or(home._description::text='Пушкинский VIP'
                          AND lower(coalesce(contract_service._description::text,'')) NOT LIKE '%контракт сотрудника%'), false) AS has_vip_visit,
         coalesce(bool_or(home._description::text='Детский развивающий центр'
                          AND lower(coalesce(contract_service._description::text,'')) NOT LIKE '%контракт сотрудника%'
                          AND lower(coalesce(contract_service._description::text,'')) NOT LIKE '%продленка%'
                          AND lower(coalesce(contract_service._description::text,'')) NOT LIKE '%продлёнка%'
                          AND lower(coalesce(contract_service._description::text,'')) NOT LIKE '%умняши%'), false) AS has_drc_visit,
         coalesce(bool_or(home._description::text='Детский развивающий центр'
                          AND (lower(coalesce(contract_service._description::text,'')) LIKE '%продленка%'
                               OR lower(coalesce(contract_service._description::text,'')) LIKE '%продлёнка%')), false) AS has_after_school_visit,
         coalesce(bool_or(home._description::text='Детский развивающий центр'
                          AND lower(coalesce(contract_service._description::text,'')) LIKE '%умняши%'), false) AS has_umnyashki_visit
  FROM base_visits b
  JOIN pushkin_club p ON p.club_ref=b.club_ref
  LEFT JOIN public._reference59 contract ON contract._idrref=b.contract_ref
  LEFT JOIN public._reference163 contract_service ON contract_service._idrref=contract._fld685rref
  LEFT JOIN public._reference132 home ON home._idrref=contract._fld687rref
  LEFT JOIN public._reference163 visit_service ON visit_service._idrref=b.visit_service_ref
  CROSS JOIN constants k
  GROUP BY b.visit_date, b.club_ref, b.client_ref
)
SELECT b.visit_date, encode(b.club_ref,'hex') AS club_id,
       md5(encode(b.client_ref,'hex')) AS client_key,
       true AS has_visit,
       coalesce(p.has_member_visit, false) AS has_member_visit,
       coalesce(p.has_guest_visit, false) AS has_guest_visit,
       coalesce(p.has_vip_visit, false) AS has_vip_visit,
       coalesce(p.has_drc_visit, false) AS has_drc_visit,
       coalesce(p.has_after_school_visit, false) AS has_after_school_visit,
       coalesce(p.has_umnyashki_visit, false) AS has_umnyashki_visit
FROM base_visit_keys b
LEFT JOIN pushkin_flags p
  ON p.visit_date=b.visit_date AND p.club_ref=b.club_ref AND p.client_ref=b.client_ref;
