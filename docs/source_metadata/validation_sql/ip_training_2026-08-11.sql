-- SV-068 / S3-IP-ADMISSION-001 — «Отчёт по ИП»: source controls.
-- Run only inside BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY.
-- BR-003 governs the dynamic bounded history. Do not substitute legacy static
-- InfoRg7006.Period predicates for the document-date bounds below.
-- BR-018 preserves PZ's observed VT4352 multiplicity: no deduplication.

WITH calendar_bounds AS (
    SELECT CASE
             WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 1 AND 3
               THEN (date_trunc('year', CURRENT_DATE) - INTERVAL '2 years')::date
             ELSE (date_trunc('year', CURRENT_DATE) - INTERVAL '1 year')::date
           END AS date_from,
           (date_trunc('year', CURRENT_DATE) + INTERVAL '1 year')::date AS date_to
), pz AS (
    SELECT i._recordertref, i._recorderrref, i._lineno,
           i._active, d._posted, d._marked,
           d._fld4306::date AS training_date,
           i._fld7009rref AS club_id,
           d._fld4322rref AS employee_id,
           i._fld7008rref AS client_id,
           client._code::text AS client_code,
           i._fld7010rref AS service_id
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._reference163 service ON service._idrref = i._fld7010rref
    JOIN public._document329 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld4322rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref = d._idrref
    CROSS JOIN calendar_bounds b
    WHERE d._fld4306::date >= b.date_from
      AND d._fld4306::date < b.date_to
      AND (encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
        OR encode(vt._fld4358rref, 'hex') = 'a0f1524d502e0d5d4c1dfeb9d5bbb3fe')
      AND state._enumorder NOT IN (2, 3)
), gp AS (
    SELECT i._recordertref, i._recorderrref, i._lineno,
           i._active, d._posted, d._marked,
           d._fld3218::date AS training_date,
           i._fld7009rref AS club_id,
           d._fld3223rref AS employee_id,
           i._fld7008rref AS client_id,
           client._code::text AS client_code,
           i._fld7010rref AS service_id
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._reference163 service ON service._idrref = i._fld7010rref
    JOIN public._document279 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld3223rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    CROSS JOIN calendar_bounds b
    WHERE d._fld3218::date >= b.date_from
      AND d._fld3218::date < b.date_to
      AND encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
      AND state._enumorder NOT IN (2, 3)
), raw AS (
    SELECT * FROM pz
    UNION ALL
    SELECT * FROM gp
), grouped AS (
    SELECT training_date, club_id, employee_id, client_id, service_id,
           count(*)::bigint AS training_count
    FROM raw
    GROUP BY 1, 2, 3, 4, 5
), clients AS (
    SELECT DISTINCT client_id, client_code
    FROM raw
), pz_events AS (
    SELECT DISTINCT _recordertref, _recorderrref, _lineno
    FROM pz
), gp_events AS (
    SELECT DISTINCT _recordertref, _recorderrref, _lineno
    FROM gp
)
SELECT 'PZ' AS control,
       count(*)::bigint AS value_1,
       count(DISTINCT (_recordertref, _recorderrref, _lineno))::bigint AS value_2,
       (count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)))::bigint AS value_3,
       count(*) FILTER (WHERE NOT _active)::bigint AS value_4,
       count(*) FILTER (WHERE NOT _posted)::bigint AS value_5,
       count(*) FILTER (WHERE _marked)::bigint AS value_6
FROM pz
UNION ALL
SELECT 'GP', count(*)::bigint,
       count(DISTINCT (_recordertref, _recorderrref, _lineno))::bigint,
       (count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)))::bigint,
       count(*) FILTER (WHERE NOT _active)::bigint,
       count(*) FILTER (WHERE NOT _posted)::bigint,
       count(*) FILTER (WHERE _marked)::bigint
FROM gp
UNION ALL
SELECT 'GRAIN', count(*)::bigint,
       (SELECT count(*) FROM grouped)::bigint,
       (SELECT sum(training_count) FROM grouped)::bigint,
       count(*) FILTER (WHERE training_date IS NULL OR club_id IS NULL
           OR employee_id IS NULL OR client_id IS NULL OR service_id IS NULL)::bigint,
       NULL::bigint, NULL::bigint
FROM raw
UNION ALL
SELECT 'BRANCH_OVERLAP',
       (SELECT count(*) FROM (SELECT * FROM pz_events INTERSECT SELECT * FROM gp_events) x)::bigint,
       NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint
UNION ALL
SELECT 'CLIENT_CODE',
       (SELECT count(*) FROM clients)::bigint,
       (SELECT count(*) FILTER (WHERE client_code IS NULL OR btrim(client_code) = '') FROM clients)::bigint,
       (SELECT count(*) - count(DISTINCT client_code) FROM clients)::bigint,
       NULL::bigint, NULL::bigint, NULL::bigint
ORDER BY control;
