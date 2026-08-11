-- SV-070: «Посещения Физкульт» — read-only controls for the current PBIT
-- branches. Execute inside BEGIN TRANSACTION READ ONLY. Control month: 2026-07.
-- Expected: technical visit key is unique; the current M/DAX grain can be
-- reduced to date × actual club × client without loss of DISTINCTCOUNT;
-- status fields are measured, not silently added as filters.

-- VF-V01: «Посещения всего». The CTE keeps current M's Document325 client
-- and actual visit-club attribution. The 12-club list implements BR-006;
-- no main-club filter is applied to this comparison branch.
WITH base AS (
    SELECT a._recordertref, a._recorderrref, a._lineno,
           a._active, d._posted, d._marked,
           a._period::date AS visit_date,
           d._fld4171rref AS document_client_id,
           a._fld7576rref AS register_client_id,
           d._fld4167rref AS document_club_id,
           a._fld7577rref AS register_club_id,
           club._description::text AS visit_club_name
    FROM public._accumrg7575 a
    JOIN public._document325 d ON d._idrref = a._recorderrref
    JOIN public._reference141x1 client ON client._idrref = d._fld4171rref
    JOIN public._reference132 club ON club._idrref = d._fld4167rref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND a._period >= DATE '2026-07-01' AND a._period < DATE '2026-08-01'
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
      AND client._code IS NOT NULL
), fizkult AS (
    SELECT * FROM base
    WHERE visit_club_name IN (
      'Автозаводский','Бурнаковский','Деловая','Корабли','Кстово','Мещера',
      'Парковая','Родионова','Советская','Спорт','Старт','Южное'
    )
), client_day AS (
    SELECT visit_date, document_club_id, document_client_id, count(*) AS raw_event_count
    FROM fizkult GROUP BY 1, 2, 3
)
SELECT count(*) AS raw_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS source_events,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS join_excess,
       (SELECT count(*) FROM client_day) AS client_day_club_rows,
       (SELECT sum(raw_event_count) FROM client_day) AS grouped_raw_event_count,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE NOT _posted) AS unposted_rows,
       count(*) FILTER (WHERE _marked) AS marked_rows,
       count(*) FILTER (WHERE document_client_id IS DISTINCT FROM register_client_id) AS client_ref_mismatches,
       count(*) FILTER (WHERE document_club_id IS DISTINCT FROM register_club_id) AS club_ref_mismatches
FROM fizkult;

-- VF-V02: «Посещения ГП». Current M filters posted Document279 and sums
-- InfoRg8675.Fld8677; it does not filter marked documents. InfoRg8675 has no
-- physical Active field, so no state filter may be inferred for that register.
WITH base AS (
    SELECT d._idrref AS lesson_id, d._posted, d._marked,
           d._fld3218::date AS event_date, d._fld3224rref AS club_id,
           club._description::text AS club_name, i._fld8677 AS attended
    FROM public._document279 d
    JOIN public._reference132 club ON club._idrref = d._fld3224rref
    JOIN public._inforg8675 i ON i._fld8676rref = d._idrref
    WHERE d._fld3218 >= DATE '2026-07-01' AND d._fld3218 < DATE '2026-08-01'
      AND d._posted = true
      AND club._description::text IN (
        'Автозаводский','Бурнаковский','Деловая','Корабли','Кстово','Мещера',
        'Парковая','Родионова','Советская','Спорт','Старт','Южное'
      )
      AND i._fld8677 IS NOT NULL
), day_club AS (
    SELECT event_date, club_id, sum(attended) AS group_program_visit_count
    FROM base GROUP BY 1, 2
)
SELECT count(*) AS source_rows, count(DISTINCT lesson_id) AS lessons,
       count(*) - count(DISTINCT lesson_id) AS lesson_join_excess,
       sum(attended) AS attended_sum,
       (SELECT sum(group_program_visit_count) FROM day_club) AS grouped_attended_sum,
       count(*) FILTER (WHERE _marked) AS marked_rows
FROM base;

-- VF-V03: coupon source. Expected: source key remains unique; matching a
-- prebooking to Document325 can be one-to-many and must be recorded rather
-- than deduplicated before reproducing current M/DAX.
WITH services_filtered AS (
    SELECT _idrref FROM public._reference163
    WHERE _parentidrref = decode('4296a4bf013441d111e7cae05001072c', 'hex')
), pz AS (
    SELECT i._recordertref, i._recorderrref, i._lineno, i._active,
           i._fld7008rref AS client_id, i._fld7009rref AS club_id,
           d._posted, d._marked, d._fld4306 AS class_start
    FROM public._inforg7006 i
    JOIN public._document329 d ON d._idrref = i._fld7007_rrref
    JOIN public._enum448 e ON e._idrref = i._fld7013rref
    JOIN services_filtered s ON s._idrref = i._fld7010rref
    WHERE i._period >= DATE '2025-01-01' AND e._enumorder = 4
      -- In the current M join a matched visit date equals class_start::date;
      -- restricting class_start to the control month is therefore equivalent.
      AND d._fld4306 >= DATE '2026-07-01' AND d._fld4306 < DATE '2026-08-01'
), matched AS (
    SELECT pz._recordertref, pz._recorderrref, pz._lineno, pz._active,
           pz._posted AS prebooking_posted, pz._marked AS prebooking_marked,
           d._posted AS visit_posted, d._marked AS visit_marked,
           d._date_time::date AS visit_date, d._fld4167rref AS visit_club_id,
           d._fld4171rref AS visit_client_id
    FROM pz
    JOIN public._document325 d ON d._fld4171rref = pz.client_id
      AND d._date_time::date = pz.class_start::date
      AND d._fld4172 <= pz.class_start
      AND d._fld4167rref = pz.club_id
    JOIN public._reference132 club ON club._idrref = d._fld4167rref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND d._date_time >= DATE '2026-07-01' AND d._date_time < DATE '2026-08-01'
      AND club._description::text IN (
        'Автозаводский','Бурнаковский','Деловая','Корабли','Кстово','Мещера',
        'Парковая','Родионова','Советская','Спорт','Старт','Южное'
      )
)
SELECT count(*) AS matched_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS source_events,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS join_excess,
       count(DISTINCT (visit_date, visit_club_id, visit_client_id)) AS client_day_club_rows,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE NOT prebooking_posted) AS unposted_prebookings,
       count(*) FILTER (WHERE prebooking_marked) AS marked_prebookings,
       count(*) FILTER (WHERE NOT visit_posted) AS unposted_visits,
       count(*) FILTER (WHERE visit_marked) AS marked_visits
FROM matched;

-- VF-V04: current «Посещения проверка ДПФУ» branch. DAX ultimately counts
-- distinct clients, while M groups source rows by date, client and actual
-- club. The test preserves the source classification and measures its joins.
WITH training_dates AS (
    SELECT _idrref AS training_id, _fld3218::date AS training_date,
           _posted, _marked
    FROM public._document279
    WHERE _posted = true AND _fld3218 >= DATE '2026-07-01' AND _fld3218 < DATE '2026-08-01'
    UNION ALL
    SELECT _idrref, _fld4306::date, _posted, _marked
    FROM public._document329
    WHERE _posted = true AND _fld4306 >= DATE '2026-07-01' AND _fld4306 < DATE '2026-08-01'
), raw AS (
    SELECT a._recordertref, a._recorderrref, a._lineno, a._active,
           td._marked AS training_marked, td.training_date,
           a._fld7577rref AS club_id, a._fld7576rref AS client_id,
           club._description::text AS club_name
    FROM public._accumrg7575 a
    JOIN training_dates td ON td.training_id = a._fld7581_rrref
    JOIN public._reference141x1 client ON client._idrref = a._fld7576rref
    JOIN public._reference132 club ON club._idrref = a._fld7577rref
    JOIN public._reference163 service ON service._idrref = a._fld7579rref
    JOIN public._reference70 direction ON direction._idrref = service._fld1733rref
    LEFT JOIN public._reference59 contract ON contract._idrref = a._fld7578_rrref
    WHERE service._fld1795rref = decode('9f007d77d46892dc47058346701d3bb6', 'hex')
      AND COALESCE(direction._fld843rref, decode('00', 'hex')) NOT IN (
        decode('9e10e872e49a551b4968a66b95c28905', 'hex'),
        decode('ac626c95655c992a471b27ca8f8812cd', 'hex')
      )
      AND COALESCE(service._description::text, '') <> 'посещение клуба'
      AND direction._description::text IN (
        'Игровой зал','Восстановительный фитнес','Боевые искусства','Детский клуб',
        'Водные программы','Групповые программы','Тренажёрный зал','Тренажерный зал'
      )
      AND contract._fld696rref IS DISTINCT FROM decode('bf4b50662e88eb7b44046ebf4849976f', 'hex')
      AND client._fld1532rref IS DISTINCT FROM decode('8e3e8dea66a1d5454387ceb554c10615', 'hex')
      AND club._description::text IN (
        'Автозаводский','Бурнаковский','Деловая','Корабли','Кстово','Мещера',
        'Парковая','Родионова','Советская','Спорт','Старт','Южное'
      )
), client_day AS (
    SELECT training_date, club_id, client_id, count(*) AS source_row_count
    FROM raw GROUP BY 1, 2, 3
)
SELECT count(*) AS raw_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS source_events,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS join_excess,
       (SELECT count(*) FROM client_day) AS client_day_club_rows,
       (SELECT sum(source_row_count) FROM client_day) AS grouped_source_rows,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) FILTER (WHERE training_marked) AS marked_training_documents
FROM raw;
