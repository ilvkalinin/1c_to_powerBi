-- SV-071: «Посещения Пушкинский» — read-only controls. Run in BEGIN
-- TRANSACTION READ ONLY. Control date D = 2026-07-15; source states are
-- measured, never added as new filters.

-- VP-V01: the agreed membership snapshot (BR-005) and current member-visit
-- source. Expected: D-start contracts are excluded, D-1 endings included;
-- event key is unique and report-level client-day grouping is lossless.
WITH constants AS (
    SELECT DATE '2026-07-15' AS d,
           decode('9b656ee141a764e44de79e83cd30c1b2', 'hex') AS clip_card_type,
           decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex') AS visit_operation,
           decode('89de5e634e304b1a44efac5ab7088373', 'hex') AS membership_service,
           decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex') AS client_type
), memberships AS (
    SELECT r._fld681rref AS client_id, r._fld671::date AS start_date,
           r._fld672::date AS end_date
    FROM public._reference59 r
    JOIN public._reference132 home_club ON home_club._idrref = r._fld687rref
    JOIN public._reference141x1 client ON client._idrref = r._fld681rref
    CROSS JOIN constants c
    WHERE home_club._description::text = 'Пушкинский'
      AND r._fld696rref <> c.clip_card_type AND client._code IS NOT NULL
), member_set AS (
    SELECT DISTINCT m.client_id
    FROM memberships m CROSS JOIN constants c
    WHERE m.start_date < c.d AND m.end_date >= c.d - 1
), visits AS (
    SELECT a._recordertref, a._recorderrref, a._lineno, a._active,
           d._posted, d._marked, a._period::date AS visit_date,
           d._fld4171rref AS client_id
    FROM public._accumrg7575 a
    JOIN public._document325 d ON d._idrref = a._recorderrref
    JOIN public._reference141x1 client ON client._idrref = d._fld4171rref
    JOIN public._reference59 contract ON contract._idrref = a._fld7578_rrref
    JOIN public._reference163 service ON service._idrref = contract._fld685rref
    JOIN public._reference132 home_club ON home_club._idrref = contract._fld687rref
    JOIN public._reference132 visit_club ON visit_club._idrref = d._fld4167rref
    CROSS JOIN constants c
    WHERE d._fld4164rref = c.visit_operation
      AND service._fld1795rref = c.membership_service
      AND home_club._description::text = 'Пушкинский'
      AND visit_club._description::text = 'Пушкинский'
      AND client._fld1532rref = c.client_type
      AND a._period >= c.d - 30 AND a._period < c.d + 1
), client_day AS (
    SELECT visit_date, client_id, count(*) AS raw_event_count
    FROM visits GROUP BY 1, 2
)
SELECT
    (SELECT count(*) FROM member_set) AS member_base_clients,
    (SELECT count(*) FROM memberships m CROSS JOIN constants c WHERE m.start_date = c.d) AS starts_on_d_excluded,
    (SELECT count(*) FROM memberships m CROSS JOIN constants c WHERE m.end_date = c.d - 1) AS ends_on_d_minus_1_included,
    count(*) AS raw_visit_rows,
    count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS source_events,
    count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS join_excess,
    (SELECT count(*) FROM client_day) AS client_day_rows,
    (SELECT sum(raw_event_count) FROM client_day) AS grouped_event_rows,
    count(*) FILTER (WHERE NOT _active) AS inactive_rows,
    count(*) FILTER (WHERE NOT _posted) AS unposted_rows,
    count(*) FILTER (WHERE _marked) AS marked_rows
FROM visits;

-- VP-V02: target client-set identity at D. Current DAX's active population,
-- after subtracting visitors on D, is exactly member visits [D-30, D). All
-- sets are intersected with the agreed member snapshot before counting.
WITH constants AS (
    SELECT DATE '2026-07-15' AS d,
           decode('9b656ee141a764e44de79e83cd30c1b2', 'hex') AS clip_card_type,
           decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex') AS visit_operation,
           decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex') AS client_type
), memberships AS (
    SELECT r._fld681rref AS client_id
    FROM public._reference59 r JOIN public._reference132 home ON home._idrref=r._fld687rref
    JOIN public._reference141x1 client ON client._idrref=r._fld681rref CROSS JOIN constants c
    WHERE home._description::text='Пушкинский' AND r._fld696rref<>c.clip_card_type
      AND client._code IS NOT NULL AND r._fld671::date<c.d AND r._fld672::date>=c.d-1
), members AS (SELECT DISTINCT client_id FROM memberships),
current_member_visits AS (
    SELECT DISTINCT a._period::date AS visit_date, d._fld4171rref AS client_id
    FROM public._accumrg7575 a JOIN public._document325 d ON d._idrref=a._recorderrref
    JOIN public._reference141x1 client ON client._idrref=d._fld4171rref
    JOIN public._reference59 contract ON contract._idrref=a._fld7578_rrref
    JOIN public._reference163 service ON service._idrref=contract._fld685rref
    JOIN public._reference132 home ON home._idrref=contract._fld687rref
    JOIN public._reference132 club ON club._idrref=d._fld4167rref CROSS JOIN constants c
    WHERE d._fld4164rref=c.visit_operation
      AND service._fld1795rref=decode('89de5e634e304b1a44efac5ab7088373', 'hex')
      AND home._description::text='Пушкинский' AND client._fld1532rref=c.client_type
      AND club._description::text='Пушкинский' AND a._period>=c.d-30 AND a._period<c.d+1
), visited_today AS (
    SELECT p.client_id FROM current_member_visits p CROSS JOIN constants c
    WHERE p.visit_date=c.d INTERSECT SELECT client_id FROM members
), active_nonvisitor AS (
    SELECT p.client_id FROM current_member_visits p CROSS JOIN constants c
    WHERE p.visit_date>=c.d-30 AND p.visit_date<c.d
    INTERSECT SELECT client_id FROM members
    EXCEPT SELECT client_id FROM visited_today
), inactive AS (
    SELECT client_id FROM members
    EXCEPT SELECT client_id FROM visited_today
    EXCEPT SELECT client_id FROM active_nonvisitor
)
SELECT (SELECT count(*) FROM members) AS member_base_count,
       (SELECT count(*) FROM visited_today) AS visited_today_count,
       (SELECT count(*) FROM active_nonvisitor) AS active_nonvisitor_count,
       (SELECT count(*) FROM inactive) AS inactive_count,
       (SELECT count(*) FROM visited_today)+(SELECT count(*) FROM active_nonvisitor)+(SELECT count(*) FROM inactive) AS component_sum;

-- VP-V03: reuse of the group-program fact for the actual Pushkinsky club.
WITH base AS (
    SELECT d._idrref AS lesson_id, d._marked, d._fld3218::date AS event_date,
           i._fld8677 AS attended
    FROM public._document279 d
    JOIN public._reference132 club ON club._idrref=d._fld3224rref
    JOIN public._inforg8675 i ON i._fld8676rref=d._idrref
    WHERE d._fld3218>=DATE '2026-07-01' AND d._fld3218<DATE '2026-08-01'
      AND d._posted=true AND club._description::text='Пушкинский' AND i._fld8677 IS NOT NULL
), daily AS (SELECT event_date, sum(attended) AS attended_sum FROM base GROUP BY 1)
SELECT count(*) AS source_rows, count(DISTINCT lesson_id) AS lessons,
       count(*)-count(DISTINCT lesson_id) AS join_excess, sum(attended) AS attended_sum,
       (SELECT sum(attended_sum) FROM daily) AS grouped_attended_sum,
       count(*) FILTER (WHERE _marked) AS marked_rows
FROM base;

-- VP-V04: non-member category classification. The legacy DRC predicate uses
-- `NOT LIKE A OR NOT LIKE B`, which does not exclude after-school visits.
-- The user-confirmed target rule uses AND and also excludes Umnyashki. This
-- control exposes the current overlap before any Stage-3 classification.
WITH base AS (
    SELECT a._recordertref, a._recorderrref, a._lineno, a._active,
           d._posted, d._marked, a._period::date AS visit_date,
           d._fld4171rref AS client_id,
           contract_service._description::text AS contract_service_name,
           visit_service._description::text AS visit_service_name,
           home._description::text AS home_club
    FROM public._accumrg7575 a
    JOIN public._document325 d ON d._idrref=a._recorderrref
    JOIN public._reference141x1 client ON client._idrref=d._fld4171rref
    LEFT JOIN public._reference59 contract ON contract._idrref=a._fld7578_rrref
    LEFT JOIN public._reference163 contract_service ON contract_service._idrref=contract._fld685rref
    LEFT JOIN public._reference132 home ON home._idrref=contract._fld687rref
    LEFT JOIN public._reference163 visit_service ON visit_service._idrref=a._fld7579rref
    JOIN public._reference132 actual ON actual._idrref=d._fld4167rref
    WHERE d._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND a._period>=DATE '2026-07-01' AND a._period<DATE '2026-08-01'
      AND client._fld1532rref=decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
      AND actual._description::text='Пушкинский'
), classified AS (
    SELECT *,
       home_club='Детский развивающий центр'
         AND lower(coalesce(contract_service_name,'')) NOT LIKE '%контракт сотрудника%'
         AND (lower(coalesce(contract_service_name,'')) NOT LIKE '%продленка%'
              OR lower(coalesce(contract_service_name,'')) NOT LIKE '%продлёнка%')
         AND lower(coalesce(contract_service_name,'')) NOT LIKE '%умняши%' AS legacy_drc,
       home_club='Детский развивающий центр'
         AND lower(coalesce(contract_service_name,'')) NOT LIKE '%контракт сотрудника%'
         AND lower(coalesce(contract_service_name,'')) NOT LIKE '%продленка%'
         AND lower(coalesce(contract_service_name,'')) NOT LIKE '%продлёнка%'
         AND lower(coalesce(contract_service_name,'')) NOT LIKE '%умняши%' AS corrected_drc,
       home_club='Детский развивающий центр'
         AND (lower(coalesce(contract_service_name,'')) LIKE '%продленка%'
              OR lower(coalesce(contract_service_name,'')) LIKE '%продлёнка%') AS after_school,
       home_club='Детский развивающий центр'
         AND lower(coalesce(contract_service_name,'')) LIKE '%умняши%' AS umnyashki,
       (lower(coalesce(visit_service_name,'')) LIKE '%гостевой визит%'
            OR lower(coalesce(visit_service_name,'')) LIKE '%гост%')
         AND lower(coalesce(visit_service_name,'')) NOT LIKE '%гость кафе%' AS guest_visit,
       home_club='Пушкинский VIP'
         AND lower(coalesce(contract_service_name,'')) NOT LIKE '%контракт сотрудника%' AS vip_visit
    FROM base
)
SELECT count(*) AS raw_visit_rows,
       count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS source_events,
       count(*)-count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS join_excess,
       count(*) FILTER (WHERE legacy_drc) AS legacy_drc_rows,
       count(*) FILTER (WHERE corrected_drc) AS corrected_drc_rows,
       count(*) FILTER (WHERE after_school) AS after_school_rows,
       count(*) FILTER (WHERE umnyashki) AS umnyashki_rows,
       count(*) FILTER (WHERE legacy_drc AND after_school) AS legacy_drc_after_school_overlap,
       count(*) FILTER (WHERE corrected_drc AND (after_school OR umnyashki)) AS corrected_drc_overlap,
       count(*) FILTER (WHERE guest_visit) AS guest_visit_rows,
       count(*) FILTER (WHERE vip_visit) AS vip_visit_rows,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE NOT _posted) AS unposted_rows,
       count(*) FILTER (WHERE _marked) AS marked_rows
FROM classified;

-- VP-V05: coupon branch reused from the Fizkult source mapping, restricted
-- to actual Pushkinsky. It retains current M's latest club-card end-date
-- condition and records join multiplicity before DAX DISTINCTCOUNT.
WITH services_filtered AS (
    SELECT _idrref FROM public._reference163
    WHERE _parentidrref=decode('4296a4bf013441d111e7cae05001072c', 'hex')
), pz AS (
    SELECT i._recordertref, i._recorderrref, i._lineno, i._active,
           i._fld7008rref AS client_id, i._fld7009rref AS club_id,
           d._posted AS prebooking_posted, d._marked AS prebooking_marked,
           d._fld4306 AS class_start
    FROM public._inforg7006 i JOIN public._document329 d ON d._idrref=i._fld7007_rrref
    JOIN public._enum448 e ON e._idrref=i._fld7013rref
    JOIN services_filtered s ON s._idrref=i._fld7010rref
    WHERE i._period>=DATE '2025-01-01' AND e._enumorder=4
      AND d._fld4306>=DATE '2026-07-01' AND d._fld4306<DATE '2026-08-01'
), matched AS (
    SELECT pz.*, d._posted AS visit_posted, d._marked AS visit_marked,
           d._date_time::date AS visit_date, d._fld4171rref AS visit_client_id,
           last_card.contract_end
    FROM pz JOIN public._document325 d ON d._fld4171rref=pz.client_id
      AND d._date_time::date=pz.class_start::date AND d._fld4172<=pz.class_start
      AND d._fld4167rref=pz.club_id
    JOIN public._reference132 club ON club._idrref=d._fld4167rref
    LEFT JOIN LATERAL (
        SELECT card._fld672 AS contract_end FROM public._reference59 card
        WHERE card._fld681rref=pz.client_id
          AND card._fld696rref=decode('bf4b50662e88eb7b44046ebf4849976f', 'hex')
          AND card._fld672>DATE '2025-01-01'
        ORDER BY card._fld672 DESC LIMIT 1
    ) last_card ON true
    WHERE d._fld4164rref=decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND d._date_time>=DATE '2026-07-01' AND d._date_time<DATE '2026-08-01'
      AND club._description::text='Пушкинский'
      AND (last_card.contract_end>pz.class_start OR last_card.contract_end IS NULL)
)
SELECT count(*) AS matched_rows,
       count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS source_events,
       count(*)-count(DISTINCT (_recordertref,_recorderrref,_lineno)) AS join_excess,
       count(DISTINCT (visit_date,visit_client_id)) AS client_day_rows,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE NOT prebooking_posted) AS unposted_prebookings,
       count(*) FILTER (WHERE prebooking_marked) AS marked_prebookings,
       count(*) FILTER (WHERE NOT visit_posted) AS unposted_visits,
       count(*) FILTER (WHERE visit_marked) AS marked_visits
FROM matched;
