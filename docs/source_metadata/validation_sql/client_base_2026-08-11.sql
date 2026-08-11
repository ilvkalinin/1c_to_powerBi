-- CB-V01..V03: exact current-M membership cohort; run in READ ONLY.
-- Expected: BR-005 excludes active_from = D, includes active_to = D-1;
-- club and network scopes are deduplicated independently.
WITH current_m AS (
 SELECT ab._fld681rref client_id, ab._fld687rref club_id,
        ab._fld671::date active_from, ab._fld672::date active_to, ab._marked
 FROM public._reference59 ab JOIN public._reference141x1 cl ON cl._idrref=ab._fld681rref
 JOIN public._reference132 club ON club._idrref=ab._fld687rref
 WHERE ab._fld672>=DATE '2021-01-01' AND ab._description::varchar NOT ILIKE '%сотруд%'
   AND ab._description::varchar NOT ILIKE '%ип%' AND ab._fld672>ab._fld671
   AND club._description::varchar<>'Детский развивающий центр'
   AND encode(ab._fld694rref,'hex') IN ('bc06e4b21430ebfb44a67a65c46d41f9','9e369ac955bf602149e17b549b0f1498','91e4594e35ce15d847c4a3f32e1e18f2')
), target AS (SELECT * FROM current_m WHERE active_from<DATE '2026-07-01' AND active_to>=DATE '2026-06-30')
SELECT count(*) raw_memberships, count(DISTINCT (club_id,client_id)) club_scope_clients,
 count(DISTINCT client_id) network_scope_clients, count(*) FILTER (WHERE _marked) marked_rows
FROM target;
