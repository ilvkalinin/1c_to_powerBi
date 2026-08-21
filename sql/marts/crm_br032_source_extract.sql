-- REVIEW ONLY — source-side compact projections for BR-032/BR-033.
-- The runner binds $1 = inclusive source horizon and $2 = exclusive source
-- horizon. CORE-001, PHONE-001 and FEEDBACK-001 additionally bind $3/$4 as
-- one transport quarter; CLUB-DAY-001 binds only $1/$2. All run in one
-- REPEATABLE READ, READ ONLY source transaction.

-- name: club_day
-- CLUB-DAY-001: Calls-report denominator. This is intentionally not derived
-- from mart.visit_client_day: it preserves additive contract-reference events.
WITH params AS (
    SELECT $1::date AS horizon_start, $2::date AS horizon_end
), source_rows AS (
    SELECT a._period::date AS event_date,
           encode(visit_club._idrref, 'hex') AS club_id,
           visit_club._description::text AS club_name,
           a._fld7578_rrref AS contract_id
    FROM public._accumrg7575 a
    JOIN public._document325 doc ON doc._idrref = a._recorderrref
    JOIN public._reference141x1 client ON client._idrref = doc._fld4171rref
    JOIN public._reference132 visit_club ON visit_club._idrref = doc._fld4167rref
    CROSS JOIN params p
    WHERE doc._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND a._period >= p.horizon_start
      AND a._period < p.horizon_end
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
      AND client._code IS NOT NULL
)
SELECT event_date, club_id, club_name, count(contract_id)::bigint AS visit_event_count
FROM source_rows
GROUP BY 1, 2, 3;


-- name: core
-- CORE-001: one compact interaction row for the union of sales and guest-tour
-- consumers. The personnel EXISTS keeps source-side current-PBIT semantics
-- without transferring employment history or multiplying interactions.
-- The created_at transport bound is safeguarded before every rebuild by
-- crm_br032_quarter_created_window.sql in the same source snapshot.
WITH params AS (
    SELECT $1::timestamp without time zone AS source_start,
           $2::timestamp without time zone AS source_end,
           $3::timestamp without time zone AS chunk_start,
           $4::timestamp without time zone AS chunk_end
), sales_candidates AS MATERIALIZED (
    SELECT i._idrref AS interaction_id,
           min(CASE WHEN interaction_phone._fld7150 IS NULL
                    THEN i._fld820 ELSE interaction_phone._fld7150 END) AS anchor_at
    FROM public._reference106 t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    LEFT JOIN public._reference225 manager ON manager._idrref = i._fld824rref
    LEFT JOIN public._inforg7146 interaction_phone
      ON interaction_phone._fld7151rref = i._idrref
    CROSS JOIN params p
    WHERE i._fld823 >= p.chunk_start - INTERVAL '71 days'
      AND i._fld823 < p.chunk_end + INTERVAL '1 day'
      AND t._fld1191rref IN (
              decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
              decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
              decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
          )
      AND NOT (t._fld1191rref = decode('99b0e03a7af94bc911ef0167b7844d74'
               , 'hex') AND t._fld1197rref IN (
                   decode('99e886b88886661011f0ae4e3da6296e', 'hex'),
                   decode('99cc8098b8acd0e411efe53f048393c3', 'hex')))
      AND (CASE WHEN interaction_phone._fld7150 IS NULL THEN i._fld820
                ELSE interaction_phone._fld7150 END) >= p.source_start
      AND (CASE WHEN interaction_phone._fld7150 IS NULL THEN i._fld820
                ELSE interaction_phone._fld7150 END) < p.source_end
      AND EXISTS (
          SELECT 1
          FROM public._inforg6291 h
          JOIN public._reference225 employment_employee
            ON employment_employee._idrref = h._fld6292rref
          JOIN public._reference101 employment_position
            ON employment_position._idrref = h._fld6296rref
          WHERE employment_employee._description = manager._description
            AND employment_position._description IN (
                'Менеджер ОП', 'Старший менеджер ОП', 'Ведущий менеджер'
            )
            AND h._fld6298 <= i._fld823
            AND coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01'),
                         TIMESTAMP '2099-12-31') >= i._fld823
      )
    GROUP BY i._idrref
), sales AS MATERIALIZED (
    SELECT interaction_id, anchor_at
    FROM sales_candidates
), guest AS MATERIALIZED (
    SELECT i._idrref AS interaction_id,
           CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                    THEN i._fld822::date ELSE i._fld820::date END AS report_date,
           CASE WHEN state._description = 'Закрыто'
                       AND i._fld830rref = decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex')
                    THEN 'completed'
                WHEN state._description = 'Запланировано'
                       AND i._fld830rref = decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex')
                    THEN 'planned'
           END AS tour_kind,
           (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                    THEN i._fld822::date ELSE i._fld820::date END)::timestamp AS anchor_at
    FROM public._reference106 t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    LEFT JOIN public._reference224 state ON state._idrref = i._fld829rref
    CROSS JOIN params p
    WHERE i._fld823 >= p.chunk_start - INTERVAL '71 days'
      AND i._fld823 < p.chunk_end + INTERVAL '1 day'
      AND i._fld831rref = decode('b538e5326d9fc9a943c11fd0e7a0e678', 'hex')
      AND t._fld1191rref = decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex')
      AND ((state._description = 'Закрыто'
            AND i._fld830rref = decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex'))
        OR (state._description = 'Запланировано'
            AND i._fld830rref = decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex')))
      AND (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                    THEN i._fld822::date ELSE i._fld820::date END)
          >= p.source_start::date
      AND (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                    THEN i._fld822::date ELSE i._fld820::date END)
          < p.source_end::date
), scoped AS (
    SELECT interaction_id, true AS sales_scope, false AS guest_scope,
           NULL::date AS report_date, NULL::text AS tour_kind, anchor_at
    FROM sales
    UNION ALL
    SELECT interaction_id, false, true, report_date, tour_kind, anchor_at
    FROM guest
), scoped_ids AS MATERIALIZED (
    SELECT interaction_id,
           bool_or(sales_scope) AS sales_scope,
           bool_or(guest_scope) AS guest_scope,
           max(report_date) AS report_date,
           max(tour_kind) AS tour_kind,
           min(anchor_at) AS anchor_at
    FROM scoped
    GROUP BY interaction_id
), scoped_chunk AS MATERIALIZED (
    SELECT s.*
    FROM scoped_ids s
    CROSS JOIN params p
    WHERE s.anchor_at >= p.chunk_start
      AND s.anchor_at < p.chunk_end
)
SELECT encode(i._idrref, 'hex') AS interaction_id,
       encode(t._idrref, 'hex') AS task_id,
       t._code::text AS task_code,
       i._fld823 AS created_at,
       i._fld820 AS started_at,
       i._fld821 AS ended_at,
       i._fld822 AS planned_at,
       i._description::text AS interaction_name,
       encode(i._fld831rref, 'hex') AS event_type_id,
       CASE encode(i._fld831rref, 'hex')
           WHEN 'b538e5326d9fc9a943c11fd0e7a0e678' THEN 'Встреча'
           WHEN 'af240c30136a9c4e4c4d477d359e0f03' THEN 'Заявка на обратный звонок'
           WHEN '8590e885ee4c688946c3e23782968752' THEN 'Входящий звонок'
           WHEN '8d7225693e34b52f450fe5181ac00cb9' THEN 'Исходящий звонок'
           WHEN '9db9fdbf6bd80f2044eb2835157b3bc8' THEN 'Обратная связь'
           WHEN '8b888f0c4a5eb1724b77b72ebeffdf6b' THEN 'Онлайн покупка'
           WHEN '8cdb19ca805f72d94dfd36278e121b82' THEN 'Отмена гостевого визита'
           WHEN '8f6da46ad3a0c51b4bb9feb594cb3b9c' THEN 'Оформление'
           WHEN 'a991e34cdfd2527449f98fb5c998a54d' THEN 'Переход по клику'
           WHEN '87c74245c038b6244d8f6f7169c0d545' THEN 'Регистрация гостевого визита'
           WHEN 'b70ab7149b54e8f240c0203b5ae78b63' THEN 'Регистрация рекомендации'
           WHEN '8d375d1bd8b128d447da1f927d95614c' THEN 'Уведомление'
           WHEN '952f4279216ec5844b0b165542d2d0d4' THEN 'Чат'
           WHEN '811e1e78f495bbd940b19032400397a3' THEN 'Входящее письмо'
           WHEN 'b86111863fbaefeb42b967aaa9ae4ce2' THEN 'Исходящее письмо'
       END AS event_type_name,
       encode(i._fld829rref, 'hex') AS state_id,
       state._description::text AS state_name,
       encode(i._fld830rref, 'hex') AS status_id,
       CASE encode(i._fld830rref, 'hex')
           WHEN 'b78f16cfde0c1e1f4f7c0ae8d942393d' THEN 'Выполнено'
           WHEN '83b62b0bd3908a65448b72ca1ec17e94' THEN 'Не выполнено'
           WHEN 'aef6c17befe0705047f834208813539a' THEN 'Отменено'
       END AS status_name,
       encode(i._fld824rref, 'hex') AS executor_id,
       executor._description::text AS executor_name,
       cancellation_reason._description::text AS cancellation_reason_name,
       encode(client._idrref, 'hex') AS client_id,
       client._code::text AS client_code,
       client._description::text AS client_name,
       client._fld1531::text AS client_phone,
       encode(club._idrref, 'hex') AS club_id,
       club._description::text AS club_name,
       CASE WHEN club._description IN ('Пушкинский', 'Пушкинский VIP')
                 THEN 'Пушкинский' ELSE 'Физкульт' END AS network_name,
       encode(funnel._idrref, 'hex') AS funnel_id,
       funnel._description::text AS funnel_name,
       encode(campaign._idrref, 'hex') AS campaign_id,
       campaign._description::text AS campaign_name,
       encode(channel._idrref, 'hex') AS channel_id,
       CASE encode(t._fld1190rref, 'hex')
           WHEN 'bc06e4b21430ebfb44a67a65c46d41f9' THEN 'New'
           WHEN '9e369ac955bf602149e17b549b0f1498' THEN 'Ex'
           WHEN '91e4594e35ce15d847c4a3f32e1e18f2' THEN 'Renew'
       END AS tenure_type_name,
       CASE encode(t._fld1204rref, 'hex')
           WHEN 'a596b91e9b85de1a4f63e088902e2513' THEN 'Действительный'
           WHEN 'bc99c42e4b5499f4422c9a94b1a2c7bc' THEN 'Бывший'
           WHEN '8b9747f5715f8b8f452e652aeaa55c8c' THEN 'Потенциальный'
       END AS client_status_name,
       s.sales_scope, s.guest_scope, s.report_date, s.tour_kind
FROM scoped_chunk s
JOIN public._reference67 i ON i._idrref = s.interaction_id
JOIN public._reference106 t ON t._idrref = i._owneridrref
LEFT JOIN public._reference224 state ON state._idrref = i._fld829rref
LEFT JOIN public._reference225 executor ON executor._idrref = i._fld824rref
LEFT JOIN public._reference202 cancellation_reason ON cancellation_reason._idrref = i._fld828rref
LEFT JOIN public._reference141x1 client ON client._idrref = t._fld1196rref
LEFT JOIN public._reference132 club ON club._idrref = t._fld1195rref
LEFT JOIN public._reference89 funnel ON funnel._idrref = t._fld1191rref
LEFT JOIN public._reference145 campaign ON campaign._idrref = t._fld1197rref
LEFT JOIN public._reference122 channel ON channel._idrref = t._fld1194rref;


-- name: phone
-- PHONE-001: only technical phone rows belonging to the compact core.
-- It repeats CORE-001's guarded created_at transport bound so no phone child
-- can be selected for an interaction omitted from the compact core.
WITH params AS (
    SELECT $1::timestamp without time zone AS source_start,
           $2::timestamp without time zone AS source_end,
           $3::timestamp without time zone AS chunk_start,
           $4::timestamp without time zone AS chunk_end
), sales_candidates AS MATERIALIZED (
    SELECT i._idrref AS interaction_id,
           min(CASE WHEN interaction_phone._fld7150 IS NULL
                    THEN i._fld820 ELSE interaction_phone._fld7150 END) AS anchor_at
    FROM public._reference106 t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    LEFT JOIN public._reference225 manager ON manager._idrref = i._fld824rref
    LEFT JOIN public._inforg7146 interaction_phone
      ON interaction_phone._fld7151rref = i._idrref
    CROSS JOIN params p
    WHERE i._fld823 >= p.chunk_start - INTERVAL '71 days'
      AND i._fld823 < p.chunk_end + INTERVAL '1 day'
      AND t._fld1191rref IN (
              decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
              decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
              decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
          )
      AND NOT (t._fld1191rref = decode('99b0e03a7af94bc911ef0167b7844d74', 'hex')
               AND t._fld1197rref IN (
                   decode('99e886b88886661011f0ae4e3da6296e', 'hex'),
                   decode('99cc8098b8acd0e411efe53f048393c3', 'hex')))
      AND (CASE WHEN interaction_phone._fld7150 IS NULL THEN i._fld820
                ELSE interaction_phone._fld7150 END) >= p.source_start
      AND (CASE WHEN interaction_phone._fld7150 IS NULL THEN i._fld820
                ELSE interaction_phone._fld7150 END) < p.source_end
      AND EXISTS (
          SELECT 1 FROM public._inforg6291 h
          JOIN public._reference225 employment_employee
            ON employment_employee._idrref = h._fld6292rref
          JOIN public._reference101 employment_position
            ON employment_position._idrref = h._fld6296rref
          WHERE employment_employee._description = manager._description
            AND employment_position._description IN
                ('Менеджер ОП', 'Старший менеджер ОП', 'Ведущий менеджер')
            AND h._fld6298 <= i._fld823
            AND coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01'),
                         TIMESTAMP '2099-12-31') >= i._fld823
      )
    GROUP BY i._idrref
), sales AS MATERIALIZED (
    SELECT interaction_id, anchor_at FROM sales_candidates
), guest AS MATERIALIZED (
    SELECT i._idrref AS interaction_id,
           (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                    THEN i._fld822::date ELSE i._fld820::date END)::timestamp AS anchor_at
    FROM public._reference106 t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    LEFT JOIN public._reference224 state ON state._idrref = i._fld829rref
    CROSS JOIN params p
    WHERE i._fld823 >= p.chunk_start - INTERVAL '71 days'
      AND i._fld823 < p.chunk_end + INTERVAL '1 day'
      AND i._fld831rref = decode('b538e5326d9fc9a943c11fd0e7a0e678', 'hex')
      AND t._fld1191rref = decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex')
      AND ((state._description = 'Закрыто'
            AND i._fld830rref = decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex'))
        OR (state._description = 'Запланировано'
            AND i._fld830rref = decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex')))
      AND (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                    THEN i._fld822::date ELSE i._fld820::date END)
          >= p.source_start::date
      AND (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                    THEN i._fld822::date ELSE i._fld820::date END)
          < p.source_end::date
), scoped AS (
    SELECT interaction_id, min(anchor_at) AS anchor_at
    FROM (
        SELECT interaction_id, anchor_at FROM sales
        UNION ALL
        SELECT interaction_id, anchor_at FROM guest
    ) candidates
    GROUP BY interaction_id
), scoped_chunk AS (
    SELECT s.interaction_id
    FROM scoped s CROSS JOIN params p
    WHERE s.anchor_at >= p.chunk_start AND s.anchor_at < p.chunk_end
)
SELECT encode(p._fld7151rref, 'hex') AS interaction_id,
       encode(p._fld7147rref, 'hex') AS phone_reference_id,
       encode(p._fld8699, 'hex') AS phone_event_id,
       p._fld7150 AS phone_at,
       (p._fld7148 IS NOT NULL
        AND p._fld7148 <> TIMESTAMP '0001-01-01') AS answered_flag
FROM scoped_chunk s
JOIN public._inforg7146 p ON p._fld7151rref = s.interaction_id
JOIN public._reference67 i ON i._idrref = s.interaction_id
CROSS JOIN params bounds
WHERE p._fld7150 >= bounds.source_start
  AND p._fld7150 < bounds.source_end;


-- name: feedback
-- FEEDBACK-001: the checked calls-template final business grain. Comments,
-- phone flags and first later non-feedback interaction are reduced on VM-1.
WITH params AS (
    SELECT $1::timestamp without time zone AS horizon_start,
           $2::timestamp without time zone AS horizon_end,
           $3::timestamp without time zone AS chunk_start,
           $4::timestamp without time zone AS chunk_end
), feedback_base AS MATERIALIZED (
    SELECT i._idrref AS interaction_ref,
           i._fld823 AS created_at,
           t._code::text AS task_code,
           t._fld1200::text AS task_description,
           i._description::text AS interaction_name,
           i._fld820 AS started_at,
           i._fld821 AS ended_at,
           i._fld822 AS planned_at,
           topic._description::text AS feedback_topic_name,
           theme._description::text AS feedback_theme,
           club._description::text AS club_name,
           funnel._description::text AS funnel_name,
           department._description::text AS department_name,
           CASE encode(i._fld830rref, 'hex')
               WHEN 'b78f16cfde0c1e1f4f7c0ae8d942393d' THEN 'Выполнено'
               WHEN '83b62b0bd3908a65448b72ca1ec17e94' THEN 'Не выполнено'
               WHEN 'aef6c17befe0705047f834208813539a' THEN 'Отменено'
           END AS status_name,
           state._description::text AS state_name,
           executor._description::text AS executor_name,
           position._description::text AS position_name,
           client._code::text AS client_code,
           client._description::text AS client_name,
           client._fld1531::text AS client_phone,
           CASE encode(t._fld1190rref, 'hex')
               WHEN 'bc06e4b21430ebfb44a67a65c46d41f9' THEN 'New'
               WHEN '9e369ac955bf602149e17b549b0f1498' THEN 'Ex'
               WHEN '91e4594e35ce15d847c4a3f32e1e18f2' THEN 'Renew'
           END AS tenure_type_name,
           campaign._description::text AS campaign_name,
           campaign._code::text AS campaign_code,
           channel._description::text AS channel_name,
           regulated._description::text AS regulated_interaction_name,
           cancellation_reason._description::text AS cancellation_reason_name
    FROM public._reference67 i
    JOIN public._reference106 t ON t._idrref = i._owneridrref
    LEFT JOIN public._reference8628 topic ON topic._idrref = t._fld8643rref
    LEFT JOIN public._inforg5810 theme_link ON theme_link._fld5811_rrref = t._idrref
    LEFT JOIN public._reference110 theme ON theme._idrref = theme_link._fld5813_rrref
    LEFT JOIN public._reference89 funnel ON funnel._idrref = t._fld1191rref
    LEFT JOIN public._reference141x1 client ON client._idrref = t._fld1196rref
    LEFT JOIN public._reference132 club ON club._idrref = t._fld1195rref
    LEFT JOIN public._reference225 executor ON executor._idrref = i._fld824rref
    LEFT JOIN public._reference202 cancellation_reason ON cancellation_reason._idrref = i._fld828rref
    LEFT JOIN public._reference224 state ON state._idrref = i._fld829rref
    LEFT JOIN public._reference122 channel ON channel._idrref = t._fld1194rref
    LEFT JOIN public._reference212 regulated ON regulated._idrref = t._fld1202rref
    LEFT JOIN public._reference101 position ON position._idrref = t._fld1199rref
    LEFT JOIN public._reference178 department ON department._idrref = t._fld8642rref
    LEFT JOIN public._reference145 campaign ON campaign._idrref = t._fld1197rref
    CROSS JOIN params p
    WHERE i._fld831rref = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
      -- Preserve the current-template lower and current-date limits, then
      -- intersect them with this transport quarter.
      AND i._fld823 > TIMESTAMP '2025-01-01'
      AND i._fld823 < CURRENT_DATE
      AND i._fld823 >= p.horizon_start
      AND i._fld823 < p.horizon_end
      AND i._fld823 >= p.chunk_start
      AND i._fld823 < p.chunk_end
      AND (i._description IS NULL OR i._description NOT LIKE '%Jivo%')
), feedback_interactions AS MATERIALIZED (
    SELECT DISTINCT interaction_ref, created_at
    FROM feedback_base
), comment_rows AS (
    SELECT f.interaction_ref,
           CASE WHEN h._fld1464 IS NULL THEN NULL
                ELSE coalesce(nullif(regexp_replace(regexp_replace(
                    substring(h._fld1464::text from '<body>(.*?)</body>'),
                    '</?p>', '', 'g'), '\\s+', ' ', 'g'), ''), h._fld1464::text)
           END AS comment_text,
           h._fld1463 AS comment_updated_at,
           f.created_at
    FROM feedback_interactions f
    LEFT JOIN public._reference137 h ON h._fld1462rref = f.interaction_ref
), phone_agg AS (
    SELECT f.interaction_ref,
           coalesce(bool_or(p._fld7148 IS NOT NULL
                            AND p._fld7148 <> TIMESTAMP '0001-01-01'), false)
             AS answered_flag
    FROM feedback_interactions f
    LEFT JOIN public._inforg7146 p ON p._fld7151rref = f.interaction_ref
    GROUP BY f.interaction_ref
), grouped AS (
    SELECT b.task_code, b.task_description, b.interaction_name,
           max(b.created_at) AS created_at,
           max(b.started_at) AS started_at,
           max(b.ended_at) AS ended_at,
           max(b.planned_at) AS planned_at,
           b.feedback_topic_name, b.feedback_theme, b.club_name, b.funnel_name,
           b.department_name, b.status_name, b.state_name, b.executor_name,
           b.position_name, b.client_code, b.client_name, b.client_phone,
           b.tenure_type_name, b.campaign_name, b.campaign_code, b.channel_name,
           b.regulated_interaction_name, b.cancellation_reason_name,
           string_agg(DISTINCT cr.comment_text, ', ' ORDER BY cr.comment_text) AS comment_text,
           min(cr.comment_updated_at) FILTER (WHERE cr.comment_updated_at > b.created_at)
             AS comment_updated_at,
           bool_or(pa.answered_flag) AS answered_flag
    FROM feedback_base b
    LEFT JOIN comment_rows cr ON cr.interaction_ref = b.interaction_ref
    LEFT JOIN phone_agg pa ON pa.interaction_ref = b.interaction_ref
    GROUP BY b.task_code, b.task_description, b.interaction_name,
             b.feedback_topic_name, b.feedback_theme, b.club_name, b.funnel_name,
             b.department_name, b.status_name, b.state_name, b.executor_name,
             b.position_name, b.client_code, b.client_name, b.client_phone,
             b.tenure_type_name, b.campaign_name, b.campaign_code, b.channel_name,
             b.regulated_interaction_name, b.cancellation_reason_name
), followup_keys AS MATERIALIZED (
    -- The current PBIT rule is keyed by task code × client code × feedback
    -- creation time.  Resolve all such keys once, rather than rescanning the
    -- follow-up branch once for every final output group.
    SELECT DISTINCT task_code, client_code, created_at
    FROM grouped
), followup AS MATERIALIZED (
    SELECT k.task_code, k.client_code, k.created_at,
           min(o._fld823) AS first_followup_at
    FROM followup_keys k
    JOIN public._reference106 ot
      ON ot._code = k.task_code::mvarchar
    JOIN public._reference67 o
      ON o._owneridrref = ot._idrref
    LEFT JOIN public._reference141x1 oc
      ON oc._idrref = ot._fld1196rref
    WHERE o._fld831rref <> decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
      AND o._fld823 > TIMESTAMP '2025-01-01'
      AND o._fld823 < CURRENT_DATE
      AND o._fld823 >= k.created_at
      AND oc._code = k.client_code::mvarchar
    GROUP BY k.task_code, k.client_code, k.created_at
), enriched AS (
    SELECT g.*, followup.first_followup_at
    FROM grouped g
    LEFT JOIN followup
      ON followup.task_code = g.task_code
     AND followup.client_code = g.client_code
     AND followup.created_at = g.created_at
)
SELECT task_code, task_description, interaction_name, created_at, started_at,
       ended_at, planned_at, feedback_topic_name, feedback_theme, club_name,
       funnel_name, department_name, status_name, state_name, executor_name,
       position_name, client_code, client_name, client_phone, tenure_type_name,
       campaign_name, campaign_code, channel_name, regulated_interaction_name,
       cancellation_reason_name, comment_text, comment_updated_at,
       first_followup_at, answered_flag,
       coalesce(first_followup_at, comment_updated_at) AS worked_at,
       coalesce(first_followup_at, comment_updated_at) IS NOT NULL AS worked_flag,
       extract(epoch FROM coalesce(first_followup_at, comment_updated_at) - created_at)
         / 60.0 AS response_minutes,
       (ended_at::date - created_at::date)::integer AS resolution_days
FROM enriched;
