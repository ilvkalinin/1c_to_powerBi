-- PII-free decision examples for the two RM-S2 blockers.
-- One source-only query; returns up to three tie groups for each class.

WITH cohort AS MATERIALIZED (
    SELECT a._idrref AS contract_id, a._fld681rref AS client_id,
           a._fld671::date AS membership_start_date, a._fld672::date AS membership_end_date
    FROM public._reference59 AS a
    JOIN public._reference141x1 AS cl ON cl._idrref = a._fld681rref
    LEFT JOIN public._document332 AS d332 ON d332._fld4422rref = a._idrref AND d332._posted = true
    LEFT JOIN public._document287 AS d287 ON d287._fld3379rref = a._idrref
    WHERE a._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe', 'hex'), decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex'))
      AND a._fld672 > DATE '2024-01-01'
      AND a._fld672 <= date_trunc('month', current_date) + interval '6 month' - interval '1 day'
      AND a._fld693 >= 30 AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%'
      AND extract(day FROM (a._fld672 - a._fld671)) >= 30 AND cl._code IS NOT NULL
      AND a._fld690 = TIMESTAMP '0001-01-01 00:00:00' AND d332._idrref IS NULL AND d287._idrref IS NULL
), next_candidates AS MATERIALIZED (
    SELECT c.contract_id, c.membership_start_date, c.membership_end_date,
           n._idrref AS next_id, n._fld670::date AS activation_date, n._fld671::date AS next_start_date,
           n._fld672::date AS next_end_date, n._fld693::numeric AS term_days, n._marked,
           CASE WHEN n._fld699rref = decode('96976725cebf51f7461429d74d3f6cbe', 'hex') THEN 'Бесплатный' ELSE 'Платный' END AS payment_category
    FROM cohort AS c JOIN public._reference59 AS n ON n._fld681rref = c.client_id
    WHERE n._fld671 > c.membership_start_date AND n._fld672 > c.membership_end_date AND n._fld672 > n._fld671
      AND n._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND n._fld699rref <> decode('9bd3ea4748457ee94b2011de6d9687d7', 'hex')
      AND ((n._fld693 >= 30 AND n._fld699rref <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex'))
        OR (n._fld693 >= 1 AND n._fld699rref = decode('96976725cebf51f7461429d74d3f6cbe', 'hex')))
      AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
), earliest AS (
    SELECT contract_id, min(next_start_date) AS next_start_date FROM next_candidates GROUP BY contract_id
), tied_next AS (
    SELECT n.*, count(*) OVER (PARTITION BY n.contract_id)::integer AS tie_size
    FROM next_candidates AS n JOIN earliest AS e USING (contract_id, next_start_date)
), sampled_next_groups AS (
    SELECT contract_id, row_number() OVER (ORDER BY encode(contract_id, 'hex'))::integer AS example_no
    FROM tied_next GROUP BY contract_id HAVING count(*) > 1 ORDER BY encode(contract_id, 'hex') LIMIT 3
), next_examples AS (
    SELECT 'NEXT_CONTRACT'::text AS tie_class, g.example_no,
           row_number() OVER (PARTITION BY t.contract_id ORDER BY encode(t.next_id, 'hex'))::integer AS candidate_no,
           t.tie_size, t.membership_end_date AS source_end_date, t.next_start_date,
           t.activation_date, t.next_end_date, t.term_days, t.payment_category, t._marked AS marked,
           NULL::timestamp AS interaction_at, NULL::text AS interaction_type,
           NULL::text AS funnel_stage, NULL::text AS fail_reason
    FROM tied_next AS t JOIN sampled_next_groups AS g USING (contract_id)
), eligible_interactions AS MATERIALIZED (
    SELECT client._idrref AS client_id, i._idrref AS interaction_id, i._fld820 AS interaction_at,
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
             ELSE 'Не классифицировано'
           END AS interaction_type,
           stage._description::text AS funnel_stage, reason._description::text AS fail_reason
    FROM public._reference67 AS i
    JOIN public._reference106 AS task ON task._idrref = i._owneridrref
    JOIN public._reference141x1 AS client ON client._idrref = task._fld1196rref
    JOIN public._reference89 AS task_type ON task_type._idrref = task._fld1191rref
    LEFT JOIN public._reference264 AS stage ON stage._idrref = task._fld1205rref
    LEFT JOIN public._reference201 AS reason ON reason._idrref = task._fld1201rref
    LEFT JOIN public._reference202 AS source_type ON source_type._idrref = i._fld828rref
    LEFT JOIN public._reference224 AS task_state ON task_state._idrref = i._fld829rref
    WHERE i._fld823 >= DATE '2023-11-01' AND task_type._description = 'Продажа клубной карты'
      AND i._fld831rref <> decode('8f6da46ad3a0c51b4bb9feb594cb3b9c', 'hex')
      AND task_state._description IS DISTINCT FROM 'Запланировано'
      AND source_type._description IS DISTINCT FROM 'Авто'
      AND client._code IS NOT NULL AND i._fld820 <> TIMESTAMP '0001-01-01 00:00:00'
), latest AS (
    SELECT client_id, max(interaction_at) AS interaction_at FROM eligible_interactions GROUP BY client_id
), tied_interactions AS (
    SELECT i.*, count(*) OVER (PARTITION BY i.client_id)::integer AS tie_size
    FROM eligible_interactions AS i JOIN latest AS l USING (client_id, interaction_at)
), sampled_interaction_groups AS (
    SELECT client_id, row_number() OVER (ORDER BY encode(client_id, 'hex'))::integer AS example_no
    FROM tied_interactions GROUP BY client_id HAVING count(*) > 1 ORDER BY encode(client_id, 'hex') LIMIT 3
), interaction_examples AS (
    SELECT 'LATEST_INTERACTION'::text AS tie_class, g.example_no,
           row_number() OVER (PARTITION BY t.client_id ORDER BY encode(t.interaction_id, 'hex'))::integer AS candidate_no,
           t.tie_size, NULL::date AS source_end_date, NULL::date AS next_start_date,
           NULL::date AS activation_date, NULL::date AS next_end_date, NULL::numeric AS term_days,
           NULL::text AS payment_category, NULL::boolean AS marked,
           t.interaction_at, t.interaction_type, t.funnel_stage, t.fail_reason
    FROM tied_interactions AS t JOIN sampled_interaction_groups AS g USING (client_id)
)
SELECT * FROM next_examples
UNION ALL
SELECT * FROM interaction_examples
ORDER BY tie_class, example_no, candidate_no;
