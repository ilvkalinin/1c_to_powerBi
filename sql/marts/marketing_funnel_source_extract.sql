-- REVIEW ONLY — two compact source-side extracts from the same
-- REPEATABLE READ READ ONLY snapshot.
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
    JOIN public._reference89 AS f
      ON f._idrref = t._fld1191rref
    LEFT JOIN public._reference132 AS club
      ON club._idrref = t._fld1195rref
    LEFT JOIN public._reference141x1 AS client
      ON client._idrref = t._fld1196rref
    LEFT JOIN public._reference145 AS campaign
      ON campaign._idrref = t._fld1197rref
    LEFT JOIN public._reference145 AS parent
      ON parent._idrref = campaign._parentidrref
    LEFT JOIN public._reference201 AS reason
      ON reason._idrref = t._fld1201rref
    LEFT JOIN public._reference264 AS stage
      ON stage._idrref = t._fld1205rref
    WHERE f._description::text = 'Продажа клубной карты'
      AND (club._description IS NULL
           OR club._description::text <> 'Детский развивающий центр')
      AND t._fld1193 >= $1::timestamp without time zone
      AND t._fld1193 < $2::timestamp without time zone
      AND NOT t._marked
      AND coalesce(reason._description::text, '') NOT IN (
          '(Не использовать) Найдено аналогичное задание',
          'Найдено аналогичное задание'
      )
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
               'Чат', 'Регистрация рекомендации', 'Регистрация гостевого визита'
             ) THEN first_interaction_type_raw
             WHEN coalesce(parent_campaign_name, '') LIKE 'Промо%' THEN 'Мероприятия'
             WHEN first_interaction_type_raw = 'Обратная связь' THEN 'Обратная связь'
             ELSE 'Прочие'
           END AS first_interaction_type
    FROM typed
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
       first_interaction_type_raw,
       first_interaction_type,
       CASE WHEN first_interaction_type IN ('Исходящий звонок', 'Чат',
                                             'Регистрация рекомендации')
            THEN 'Накопленный трафик (исх.)'
            ELSE 'Накопленный трафик (вх.)' END AS traffic_direction,
       1::smallint AS task_count
FROM classified;

-- name: task_contract
WITH scoped_tasks AS MATERIALIZED (
    SELECT t._idrref AS task_id, t._fld1193::date AS task_date
    FROM public._reference106 AS t
    JOIN public._reference89 AS f ON f._idrref = t._fld1191rref
    LEFT JOIN public._reference132 AS club ON club._idrref = t._fld1195rref
    LEFT JOIN public._reference201 AS reason ON reason._idrref = t._fld1201rref
    WHERE f._description::text = 'Продажа клубной карты'
      AND (club._description IS NULL
           OR club._description::text <> 'Детский развивающий центр')
      AND t._fld1193 >= $1::timestamp without time zone
      AND t._fld1193 < $2::timestamp without time zone
      AND NOT t._marked
      AND coalesce(reason._description::text, '') NOT IN (
          '(Не использовать) Найдено аналогичное задание',
          'Найдено аналогичное задание'
      )
)
SELECT DISTINCT
       encode(st.task_id, 'hex') AS task_id,
       encode(c._idrref, 'hex') AS contract_id,
       c._description::text AS contract_name,
       encode(client._idrref, 'hex') AS contract_client_key,
       client._code::text AS contract_client_code,
       c._fld670::date AS activation_date,
       (c._fld670::date >= st.task_date) AS is_conversion_qualified,
       CASE
         WHEN c._fld696rref = decode('b3810658562bb24d4270435597b56bd7', 'hex') THEN 'Детские секции'
         WHEN service._fld1741rref = decode('80d300505681013811e4d84b6c6561d9', 'hex') THEN 'Взрослые'
         WHEN service._fld1741rref = decode('80d300505681013811e4d85d67cfb97d', 'hex') THEN 'Дети'
         WHEN service._fld1741rref = decode('80d300505681013811e4d85d6e92a534', 'hex') THEN 'Юниоры'
         ELSE 'Взрослые'
       END AS contract_age_group,
       CASE WHEN c._fld699rref = decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
            THEN 'Рекарринг' ELSE 'Предоплата' END AS contract_payment_type,
       CASE
         WHEN c._fld693 < 8 THEN '001-007'
         WHEN c._fld693 < 31 THEN '008-030'
         WHEN c._fld693 < 181 THEN '031-180'
         WHEN c._fld693 < 365 THEN '181-364'
         ELSE '365+'
       END AS contract_duration_group,
       CASE WHEN c._fld670::date >= st.task_date THEN 1 ELSE 0 END::smallint
         AS contract_count
FROM scoped_tasks AS st
JOIN public._inforg6798 AS r ON r._fld6799rref = st.task_id
JOIN public._reference59 AS c ON c._idrref = r._fld6800_rrref
LEFT JOIN public._reference141x1 AS client ON client._idrref = c._fld681rref
LEFT JOIN public._reference163 AS service ON service._idrref = c._fld685rref
WHERE r._fld6802
  AND c._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
  AND c._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
  AND c._fld670 IS NOT NULL;
