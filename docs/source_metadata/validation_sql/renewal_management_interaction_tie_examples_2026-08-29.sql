-- PII-free examples for RM-S2-05 only.
WITH eligible AS MATERIALIZED (
    SELECT client._idrref AS client_id,i._idrref AS interaction_id,i._fld820 AS interaction_at,
           CASE encode(i._fld831rref,'hex')
             WHEN 'b538e5326d9fc9a943c11fd0e7a0e678' THEN 'Встреча' WHEN 'af240c30136a9c4e4c4d477d359e0f03' THEN 'Заявка на обратный звонок'
             WHEN '8590e885ee4c688946c3e23782968752' THEN 'Входящий звонок' WHEN '8d7225693e34b52f450fe5181ac00cb9' THEN 'Исходящий звонок'
             WHEN '9db9fdbf6bd80f2044eb2835157b3bc8' THEN 'Обратная связь' WHEN '8b888f0c4a5eb1724b77b72ebeffdf6b' THEN 'Онлайн покупка'
             WHEN '8cdb19ca805f72d94dfd36278e121b82' THEN 'Отмена гостевого визита' WHEN 'a991e34cdfd2527449f98fb5c998a54d' THEN 'Переход по клику'
             WHEN '87c74245c038b6244d8f6f7169c0d545' THEN 'Регистрация гостевого визита' WHEN 'b70ab7149b54e8f240c0203b5ae78b63' THEN 'Регистрация рекомендации'
             WHEN '8d375d1bd8b128d447da1f927d95614c' THEN 'Уведомление' WHEN '952f4279216ec5844b0b165542d2d0d4' THEN 'Чат'
             WHEN '811e1e78f495bbd940b19032400397a3' THEN 'Входящее письмо' WHEN 'b86111863fbaefeb42b967aaa9ae4ce2' THEN 'Исходящее письмо'
             ELSE 'Не классифицировано' END AS interaction_type,
           stage._description::text AS funnel_stage,reason._description::text AS fail_reason
    FROM public._reference67 i JOIN public._reference106 task ON task._idrref=i._owneridrref
    JOIN public._reference141x1 client ON client._idrref=task._fld1196rref JOIN public._reference89 task_type ON task_type._idrref=task._fld1191rref
    LEFT JOIN public._reference264 stage ON stage._idrref=task._fld1205rref LEFT JOIN public._reference201 reason ON reason._idrref=task._fld1201rref
    LEFT JOIN public._reference202 source_type ON source_type._idrref=i._fld828rref LEFT JOIN public._reference224 task_state ON task_state._idrref=i._fld829rref
    WHERE i._fld823 >= DATE '2023-11-01' AND task_type._description='Продажа клубной карты'
      AND i._fld831rref <> decode('8f6da46ad3a0c51b4bb9feb594cb3b9c','hex') AND task_state._description IS DISTINCT FROM 'Запланировано'
      AND source_type._description IS DISTINCT FROM 'Авто' AND client._code IS NOT NULL AND i._fld820 <> TIMESTAMP '0001-01-01 00:00:00'
), latest AS (SELECT client_id,max(interaction_at) AS interaction_at FROM eligible GROUP BY client_id),
tied AS (SELECT i.*,count(*) OVER (PARTITION BY i.client_id)::integer AS tie_size FROM eligible i JOIN latest l USING(client_id,interaction_at)),
groups AS (
    SELECT client_id,row_number() OVER (ORDER BY encode(client_id,'hex'))::integer AS example_no
    FROM tied GROUP BY client_id
    HAVING count(*)>1
       AND count(DISTINCT concat_ws('|',interaction_type,coalesce(funnel_stage,'∅'),coalesce(fail_reason,'∅')))>1
    ORDER BY encode(client_id,'hex') LIMIT 3
)
SELECT g.example_no,row_number() OVER (PARTITION BY t.client_id ORDER BY encode(t.interaction_id,'hex'))::integer AS candidate_no,t.tie_size,
       t.interaction_at,t.interaction_type,t.funnel_stage,t.fail_reason
FROM tied t JOIN groups g USING(client_id)
ORDER BY example_no,candidate_no;
