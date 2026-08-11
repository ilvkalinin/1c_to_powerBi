-- SV-068 — «Отчёт по ИП»: read-only source and target-grain controls.
-- Run only inside BEGIN TRANSACTION READ ONLY. Values describe the live snapshot
-- of 2026-08-11 and may naturally change with new source events.
-- Expected invariant: PZ preserves its observed legacy join excess; GP has no
-- join excess; no inactive/unposted/marked source rows; branches do not overlap.

WITH pz AS (
    SELECT i._recordertref, i._recorderrref, i._lineno,
           i._active, d._posted, d._marked
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._document329 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld4322rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref = d._idrref
    WHERE i._period >= DATE '2024-01-01'
      AND (encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
        OR encode(vt._fld4358rref, 'hex') = 'a0f1524d502e0d5d4c1dfeb9d5bbb3fe')
      AND state._enumorder NOT IN (2, 3)
), gp AS (
    SELECT i._recordertref, i._recorderrref, i._lineno,
           i._active, d._posted, d._marked
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._document279 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld3223rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    WHERE i._period >= DATE '2024-01-01'
      AND encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
      AND state._enumorder NOT IN (2, 3)
)
SELECT 'PZ' AS branch,
       count(*) AS pbit_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS source_events,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS join_excess,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE NOT _posted) AS unposted_rows,
       count(*) FILTER (WHERE _marked) AS marked_rows
FROM pz
UNION ALL
SELECT 'GP', count(*), count(DISTINCT (_recordertref, _recorderrref, _lineno)),
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)),
       count(*) FILTER (WHERE NOT _active), count(*) FILTER (WHERE NOT _posted),
       count(*) FILTER (WHERE _marked)
FROM gp;

-- Branch disjointness by the technical InfoRg7006 event key.
WITH pz AS (
    SELECT i._recordertref, i._recorderrref, i._lineno
    FROM public._inforg7006 i
    JOIN public._document329 d ON d._idrref = i._fld7007_rrref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref = d._idrref
    WHERE i._period >= DATE '2024-01-01'
      AND (encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
        OR encode(vt._fld4358rref, 'hex') = 'a0f1524d502e0d5d4c1dfeb9d5bbb3fe')
      AND state._enumorder NOT IN (2, 3)
), gp AS (
    SELECT i._recordertref, i._recorderrref, i._lineno
    FROM public._inforg7006 i
    JOIN public._document279 d ON d._idrref = i._fld7007_rrref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    WHERE i._period >= DATE '2024-01-01'
      AND encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
      AND state._enumorder NOT IN (2, 3)
)
SELECT count(*) AS cross_branch_event_overlap
FROM (SELECT DISTINCT * FROM pz INTERSECT SELECT DISTINCT * FROM gp) overlap;

-- Target-grain control. Expected: SUM(training_count) = raw_rows and no NULL
-- grain component. This is intentionally a count of current PBIT rows: BR-018
-- retains PZ's legacy multiplicity instead of deduplicating source events.
WITH pz AS (
    SELECT d._fld4306::date AS training_date, i._fld7009rref AS club_id,
           d._fld4322rref AS employee_id, i._fld7008rref AS client_id,
           i._fld7010rref AS service_id
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._document329 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld4322rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref = d._idrref
    WHERE i._period >= DATE '2024-01-01'
      AND (encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
        OR encode(vt._fld4358rref, 'hex') = 'a0f1524d502e0d5d4c1dfeb9d5bbb3fe')
      AND state._enumorder NOT IN (2, 3)
), gp AS (
    SELECT d._fld3218::date, i._fld7009rref, d._fld3223rref,
           i._fld7008rref, i._fld7010rref
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._document279 d ON d._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = d._fld3223rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    WHERE i._period >= DATE '2024-01-01'
      AND encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
      AND state._enumorder NOT IN (2, 3)
), raw AS (
    SELECT * FROM pz UNION ALL SELECT * FROM gp
), grouped AS (
    SELECT training_date, club_id, employee_id, client_id, service_id,
           count(*)::bigint AS training_count
    FROM raw
    GROUP BY 1, 2, 3, 4, 5
)
SELECT count(*) AS raw_rows,
       (SELECT count(*) FROM grouped) AS target_grain_rows,
       (SELECT sum(training_count) FROM grouped) AS training_count_sum,
       count(*) FILTER (WHERE training_date IS NULL OR club_id IS NULL
           OR employee_id IS NULL OR client_id IS NULL OR service_id IS NULL)
           AS null_grain_rows
FROM raw;
