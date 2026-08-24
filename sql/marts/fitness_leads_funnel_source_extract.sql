-- REVIEWED SOURCE EXTRACT — execute only through
-- scripts/load_fitness_leads_funnel.py in one REPEATABLE READ, READ ONLY
-- source transaction.  No source object is created or changed.
-- Bind $1::timestamp without time zone = BR-003 inclusive start;
--      $2::timestamp without time zone = BR-003 exclusive end.
-- At 2026-08-24 the bounds are [2025-01-01, 2027-01-01).

-- name: task
WITH task_base AS MATERIALIZED (
    SELECT t._idrref,
           t._code::text AS task_code,
           t._fld1193 AS task_created_at,
           t._fld1192 AS closed_at,
           t._fld8772 AS forced_closed_at,
           t._fld1190rref AS tenure_id,
           t._fld8712rref AS first_interaction_id,
           f._idrref AS funnel_id,
           f._description::text AS funnel_name,
           club._idrref AS club_id,
           club._description::text AS club_name,
           client._idrref AS client_id,
           client._code::text AS client_code,
           campaign._idrref AS campaign_id,
           campaign._description::text AS campaign_name,
           parent._description::text AS parent_campaign_name,
           reason._description::text AS unsuccessful_reason,
           stage._description::text AS funnel_stage_name
    FROM public._reference106 AS t
    JOIN public._reference89 AS f ON f._idrref = t._fld1191rref
    LEFT JOIN public._reference132 AS club ON club._idrref = t._fld1195rref
    LEFT JOIN public._reference141x1 AS client ON client._idrref = t._fld1196rref
    LEFT JOIN public._reference145 AS campaign ON campaign._idrref = t._fld1197rref
    LEFT JOIN public._reference145 AS parent ON parent._idrref = campaign._parentidrref
    LEFT JOIN public._reference201 AS reason ON reason._idrref = t._fld1201rref
    LEFT JOIN public._reference264 AS stage ON stage._idrref = t._fld1205rref
    WHERE t._fld1191rref IN (
        decode('99ad9b75dc73f34911eee5eefdcdd3b4', 'hex'),
        decode('99f6efa9e59a276811f0fcebecd498be', 'hex'),
        decode('99b19ba3029d764511ef394a0464555f', 'hex'),
        decode('99ad9b75dc73f34911eee5ea6f34a13b', 'hex')
    )
      AND t._fld1193 >= $1::timestamp without time zone
      AND t._fld1193 < $2::timestamp without time zone
      AND NOT t._marked
      AND coalesce(reason._description::text, '') NOT IN (
          '(Не использовать) Найдено аналогичное задание',
          'Найдено аналогичное задание'
      )
), dpfu_daily AS MATERIALIZED (
    -- Exact current PBIT «ДПФУ факт» branches, aggregated at its native
    -- client-day grain before the task-window lookup.
    WITH main_data AS (
        SELECT a._period::date AS training_date, clients._code::text AS client_code
        FROM public._accumrg7575 AS a
        LEFT JOIN public._reference141x1 AS clients ON clients._idrref = a._fld7576rref
        LEFT JOIN public._reference163 AS service ON service._idrref = a._fld7579rref
        LEFT JOIN public._reference70 AS service_group ON service._fld1733rref = service_group._idrref
        WHERE a._period >= $1::timestamp without time zone
          AND a._period < $2::timestamp without time zone
          AND service._fld1795rref = '\x9f007d77d46892dc47058346701d3bb6'::bytea
          AND service_group._fld843rref NOT IN (
              '\x9e10e872e49a551b4968a66b95c28905'::bytea,
              '\xac626c95655c992a471b27ca8f8812cd'::bytea
          )
          AND cast(service._description AS varchar(1000)) <> 'посещение клуба'
          AND service_group._description IN (
              'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
              'Детский клуб', 'Водные программы', 'Групповые программы',
              'Тренажёрный зал', 'Тренажерный зал'
          )
          AND a._fld7585 IS NOT NULL AND a._fld7585 <> 0

        UNION ALL

        SELECT a._period::date AS training_date, clients._code::text AS client_code
        FROM public._accumrg7646 AS a
        LEFT JOIN public._reference141x1 AS clients ON clients._idrref = a._fld7648rref
        LEFT JOIN public._reference163 AS service ON service._idrref = a._fld7649rref
        LEFT JOIN public._reference70 AS service_group ON service._fld1733rref = service_group._idrref
        WHERE a._period >= $1::timestamp without time zone
          AND a._period < $2::timestamp without time zone
          AND service._fld1795rref NOT IN (
              '\x9f007d77d46892dc47058346701d3bb6'::bytea,
              '\x89de5e634e304b1a44efac5ab7088373'::bytea,
              '\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea
          )
          AND service_group._fld843rref NOT IN (
              '\x9e10e872e49a551b4968a66b95c28905'::bytea,
              '\xac626c95655c992a471b27ca8f8812cd'::bytea
          )
          AND cast(service._description AS varchar(1000)) <> 'посещение клуба'
          AND service_group._description IN (
              'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
              'Детский клуб', 'Водные программы', 'Групповые программы',
              'Тренажёрный зал', 'Тренажерный зал'
          )
          AND a._fld7657 IS NOT NULL AND a._fld7657 <> 0
    ), ip_data AS (
        -- The VT4352 join is intentionally retained: PBIT counts its rows.
        SELECT r._period::date AS training_date, client._code::text AS client_code
        FROM public._inforg7006 AS r
        JOIN public._reference141x1 AS client ON client._idrref = r._fld7008rref
        JOIN public._reference132 AS club ON club._idrref = r._fld7009rref
        JOIN public._document329 AS doc ON doc._idrref = r._fld7007_rrref
        JOIN public._reference225 AS program ON program._idrref = doc._fld4322rref
        JOIN public._enum448 AS status ON status._idrref = r._fld7013rref
        LEFT JOIN public._document329_vt4352 AS vt ON vt._document329_idrref = doc._idrref
        LEFT JOIN public._reference163 AS service ON service._idrref = r._fld7010rref
        WHERE r._period >= DATE '2024-01-01'
          AND (
              r._fld7010rref = decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
              OR vt._fld4358rref = decode('a0f1524d502e0d5d4c1dfeb9d5bbb3fe', 'hex')
          )
          AND status._enumorder NOT IN (2, 3)
          AND service._description NOT IN (
              'Анализ состава тела ACCUNIQ', 'Инструктаж в тренажерном зале',
              'Купон: персональная тренировка', 'Купон: стартовая тренировка'
          )
    )
    SELECT training_date, client_code, count(*)::bigint AS training_events
    FROM (
        SELECT training_date, client_code FROM main_data
        UNION ALL
        SELECT training_date, client_code FROM ip_data
    ) AS combined
    GROUP BY training_date, client_code
), typed AS (
    SELECT *,
           CASE tenure_id
             WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex') THEN 'New'
             WHEN decode('9e369ac955bf602149e17b549b0f1498', 'hex') THEN 'Ex'
             WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex') THEN 'Renew'
             ELSE NULL
           END AS tenure_type,
           CASE first_interaction_id
             WHEN decode('b538e5326d9fc9a943c11fd0e7a0e678', 'hex') THEN 'Встреча'
             WHEN decode('af240c30136a9c4e4c4d477d359e0f03', 'hex') THEN 'Заявка на обратный звонок'
             WHEN decode('8590e885ee4c688946c3e23782968752', 'hex') THEN 'Входящий звонок'
             WHEN decode('8d7225693e34b52f450fe5181ac00cb9', 'hex') THEN 'Исходящий звонок'
             WHEN decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex') THEN 'Обратная связь'
             WHEN decode('8b888f0c4a5eb1724b77b72ebeffdf6b', 'hex') THEN 'Онлайн покупка'
             WHEN decode('8cdb19ca805f72d94dfd36278e121b82', 'hex') THEN 'Отмена гостевого визита'
             WHEN decode('8f6da46ad3a0c51b4bb9feb594cb3b9c', 'hex') THEN 'Оформление'
             WHEN decode('a991e34cdfd2527449f98fb5c998a54d', 'hex') THEN 'Переход по клику'
             WHEN decode('87c74245c038b6244d8f6f7169c0d545', 'hex') THEN 'Регистрация гостевого визита'
             WHEN decode('b70ab7149b54e8f240c0203b5ae78b63', 'hex') THEN 'Регистрация рекомендации'
             WHEN decode('8d375d1bd8b128d447da1f927d95614c', 'hex') THEN 'Уведомление'
             WHEN decode('952f4279216ec5844b0b165542d2d0d4', 'hex') THEN 'Чат'
             WHEN decode('811e1e78f495bbd940b19032400397a3', 'hex') THEN 'Входящее письмо'
             WHEN decode('b86111863fbaefeb42b967aaa9ae4ce2', 'hex') THEN 'Исходящее письмо'
             ELSE NULL
           END AS first_interaction_type_raw
    FROM task_base
), classified AS (
    SELECT *,
           CASE
             WHEN first_interaction_type_raw IN (
                 'Встреча', 'Входящий звонок', 'Исходящий звонок', 'Оформление',
                 'Чат', 'Регистрация рекомендации', 'Уведомление',
                 'Регистрация гостевого визита'
             ) THEN first_interaction_type_raw
             WHEN coalesce(parent_campaign_name, '') LIKE 'Промо%' THEN 'Мероприятия'
             WHEN first_interaction_type_raw = 'Обратная связь' THEN 'Обратная связь'
             ELSE 'Прочие'
           END AS first_interaction_type
    FROM typed
), outcome AS (
    -- Aggregate once per task.  This is algebraically the same PBIT client/day
    -- window but avoids rescanning the materialized daily set per task.
    SELECT c.*, d.training_events AS dpfu_training_count
    FROM classified AS c
    LEFT JOIN (
        SELECT t._idrref, sum(dd.training_events)::bigint AS training_events
        FROM task_base AS t
        LEFT JOIN dpfu_daily AS dd
          ON dd.client_code = t.client_code
         AND dd.training_date >= t.task_created_at::date
         AND dd.training_date <= t.task_created_at::date + 45
        GROUP BY t._idrref
    ) AS d ON d._idrref = c._idrref
)
SELECT encode(_idrref, 'hex') AS task_id,
       task_code,
       task_created_at,
       task_created_at::date AS task_date,
       closed_at,
       forced_closed_at,
       encode(funnel_id, 'hex') AS funnel_id,
       funnel_name,
       encode(club_id, 'hex') AS club_id,
       club_name,
       encode(client_id, 'hex') AS client_key,
       client_code,
       tenure_type,
       encode(campaign_id, 'hex') AS campaign_id,
       campaign_name,
       coalesce(parent_campaign_name, 'НетРодителя') AS parent_campaign_name,
       unsuccessful_reason,
       funnel_stage_name,
       first_interaction_type,
       (coalesce(funnel_stage_name, '') IN (
           'Клиент посетил тренировку ДПФУ',
           'Клиент посетил триенировку по купону',
           'Клиент записан на треинровку ДПФУ',
           'Клиент записан на купон',
           'Клиент записан на тренировку',
           'Клиент посетил тренировку'
       )) AS has_booking,
       CASE
           WHEN funnel_stage_name IN (
               'Пришел на тренировку', 'Пришел на тренировку ДПФУ',
               'Пришел на тренировку купон'
           ) THEN 1::bigint
           WHEN funnel_name IN ('Потребление ДСУ Физкульт', 'Потребление ДСУ WCL') THEN 0::bigint
           ELSE dpfu_training_count
       END AS training_count,
       CASE
           WHEN funnel_stage_name IN (
               'Пришел на тренировку', 'Пришел на тренировку ДПФУ',
               'Пришел на тренировку купон'
           ) THEN true
           WHEN funnel_name IN ('Потребление ДСУ Физкульт', 'Потребление ДСУ WCL') THEN false
           ELSE coalesce(dpfu_training_count, 0) > 0
       END AS has_paid_training_45d,
       1::smallint AS task_count
FROM outcome;

-- name: task_service
WITH task_base AS MATERIALIZED (
    SELECT t._idrref,
           t._fld1192 AS closed_at,
           t._fld8772 AS forced_closed_at,
           t._fld1193::date AS task_date,
           client._code::text AS client_code
    FROM public._reference106 AS t
    LEFT JOIN public._reference141x1 AS client ON client._idrref = t._fld1196rref
    LEFT JOIN public._reference201 AS reason ON reason._idrref = t._fld1201rref
    WHERE t._fld1191rref IN (
        decode('99ad9b75dc73f34911eee5eefdcdd3b4', 'hex'),
        decode('99f6efa9e59a276811f0fcebecd498be', 'hex'),
        decode('99b19ba3029d764511ef394a0464555f', 'hex'),
        decode('99ad9b75dc73f34911eee5ea6f34a13b', 'hex')
    )
      AND t._fld1193 >= $1::timestamp without time zone
      AND t._fld1193 < $2::timestamp without time zone
      AND NOT t._marked
      AND coalesce(reason._description::text, '') NOT IN (
          '(Не использовать) Найдено аналогичное задание',
          'Найдено аналогичное задание'
      )
), direct_documents AS MATERIALIZED (
    -- Literal source of current Задания[Услуга].  It intentionally has no
    -- booking state/VT filters: those belong only to the fallback PBIT table.
    SELECT _idrref, _fld4316rref AS service_ref
    FROM public._document329
    WHERE _fld4306 >= $1::timestamp without time zone
      AND _fld4306 < $2::timestamp without time zone
    UNION ALL
    SELECT _idrref, _fld3226rref AS service_ref
    FROM public._document279
    WHERE _fld3218 >= $1::timestamp without time zone
      AND _fld3218 < $2::timestamp without time zone
), direct_match AS MATERIALIZED (
    SELECT t._idrref,
           t.closed_at,
           service._description::text AS service_name
    FROM task_base AS t
    JOIN public._inforg7006 AS r ON r._period = t.closed_at
    JOIN public._reference141x1 AS client
      ON client._idrref = r._fld7008rref
     AND client._code::text = t.client_code
    JOIN direct_documents AS d ON d._idrref = r._fld7007_rrref
    LEFT JOIN public._reference163 AS service ON service._idrref = d.service_ref
    GROUP BY t._idrref, t.closed_at, service._description
), booking_service AS MATERIALIZED (
    -- Literal source of current PBIT table «Записи».
    SELECT r._period::date AS booking_date,
           client._code::text AS client_code,
           service._description::text AS service_name
    FROM public._inforg7006 AS r
    JOIN public._reference141x1 AS client ON client._idrref = r._fld7008rref
    JOIN public._document329 AS doc ON doc._idrref = r._fld7007_rrref
    JOIN public._enum448 AS status ON status._idrref = r._fld7013rref
    LEFT JOIN public._reference163 AS service ON service._idrref = r._fld7010rref
    LEFT JOIN public._document329_vt4352 AS vt ON vt._document329_idrref = doc._idrref
    WHERE doc._fld4306 >= $1::timestamp without time zone
      AND status._enumorder = 1
      AND r._fld7010rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
      AND vt._fld4358rref <> decode('a0f1524d502e0d5d4c1dfeb9d5bbb3fe', 'hex')
      AND service._parentidrref <> decode('4296a4bf013441d111e7cae05001072c', 'hex')
    GROUP BY r._period::date, client._code, service._description

    UNION ALL

    SELECT r._period::date AS booking_date,
           client._code::text AS client_code,
           service._description::text AS service_name
    FROM public._inforg7006 AS r
    JOIN public._reference141x1 AS client ON client._idrref = r._fld7008rref
    JOIN public._document279 AS doc ON doc._idrref = r._fld7007_rrref
    JOIN public._enum448 AS status ON status._idrref = r._fld7013rref
    LEFT JOIN public._reference163 AS service ON service._idrref = r._fld7010rref
    WHERE doc._fld3218 >= $1::timestamp without time zone
      AND status._enumorder = 1
      AND r._fld7010rref <> decode('bcd000505688c8b011ee0a8ba155d4a1', 'hex')
    GROUP BY r._period::date, client._code, service._description
), direct_task AS MATERIALIZED (
    SELECT DISTINCT _idrref
    FROM direct_match
    WHERE service_name IS NOT NULL
), direct_rows AS (
    SELECT encode(d._idrref, 'hex') AS task_id,
           d.service_name,
           'DIRECT_CURRENT'::text AS service_source,
           d.closed_at::date AS service_date
    FROM direct_match AS d
    WHERE d.service_name IS NOT NULL
), fallback_candidates AS MATERIALIZED (
    -- Set-based equivalent of DAX: first select each eligible booking day for
    -- tasks with no direct nonblank service; then select the earliest day.
    SELECT t._idrref, b.booking_date, b.service_name
    FROM task_base AS t
    LEFT JOIN direct_task AS direct ON direct._idrref = t._idrref
    JOIN booking_service AS b
      ON b.client_code = t.client_code
     AND b.booking_date::timestamp without time zone >= t.task_date::timestamp without time zone
     AND b.booking_date::timestamp without time zone <= least(
         t.closed_at,
         t.forced_closed_at,
         (t.task_date + 45)::timestamp without time zone
     )
    WHERE direct._idrref IS NULL
      AND b.service_name IS NOT NULL
), fallback_first_day AS MATERIALIZED (
    SELECT _idrref, min(booking_date) AS booking_date
    FROM fallback_candidates
    GROUP BY _idrref
), fallback_rows AS (
    SELECT encode(c._idrref, 'hex') AS task_id,
           min(c.service_name)::text AS service_name,
           'FALLBACK_EARLIEST_DAX_MIN'::text AS service_source,
           c.booking_date AS service_date
    FROM fallback_candidates AS c
    JOIN fallback_first_day AS first_day
      ON first_day._idrref = c._idrref
     AND first_day.booking_date = c.booking_date
    GROUP BY c._idrref, c.booking_date
)
SELECT task_id, service_name, service_source, service_date
FROM direct_rows
UNION ALL
SELECT task_id, service_name, service_source, service_date
FROM fallback_rows;
