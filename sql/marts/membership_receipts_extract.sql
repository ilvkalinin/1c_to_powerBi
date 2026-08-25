-- Source projection for the two shared membership marts.
-- Parameters $1/$2 are the half-open BR-003 horizon [start, end).
-- This query is read only and is executed on the 1C PostgreSQL source.
WITH
constants AS (
    SELECT decode(repeat('00', 16), 'hex') AS zero_ref
),
access_time_by_product AS (
    SELECT i._fld8603rref AS product_ref, min(r._description::text) AS access_time
    FROM public._inforg8595 i
    JOIN public._reference109 r ON r._idrref = i._fld8599rref
    JOIN public._reference109 payment ON payment._idrref = i._fld8597rref
    WHERE payment._description IS NOT NULL
    GROUP BY 1
),
scoped_contract_refs AS (
    SELECT DISTINCT a._fld7371rref AS contract_ref
    FROM public._accumrg7370 a
    WHERE a._period >= $1::date AND a._period < $2::date
      AND a._fld7371rref <> (SELECT zero_ref FROM constants)
      AND a._recordertref=ANY(ARRAY[
        decode('0000013d','hex'),decode('0000013c','hex'),decode('0000011d','hex'),
        decode('00000130','hex'),decode('0000015a','hex'),decode('00000147','hex'),
        decode('0000013b','hex'),decode('0000014b','hex'),decode('00000131','hex'),
        decode('0000014d','hex'),decode('00000153','hex'),decode('00000154','hex'),
        decode('00000128','hex')
      ])
),
contract_base AS (
    SELECT c._idrref AS contract_ref,
           c._fld681rref AS client_ref,
           nullif(encode(c._idrref, 'hex'), repeat('0', 32)) AS contract_id,
           nullif(encode(c._fld681rref, 'hex'), repeat('0', 32)) AS client_key,
           nullif(encode(c._fld687rref, 'hex'), repeat('0', 32)) AS access_club_id,
           nullif(encode(c._fld701rref, 'hex'), repeat('0', 32)) AS sales_point_club_id,
           nullif(encode(c._fld683rref, 'hex'), repeat('0', 32)) AS manager_id,
           nullif(encode(c._fld685rref, 'hex'), repeat('0', 32)) AS product_id,
           p._description::text AS product_name,
           p._fld1733rref AS product_category_ref,
           p._fld1756::numeric AS product_freeze_days,
           c._fld670::date AS activation_date,
           c._fld671::date AS start_date,
           c._fld672::date AS end_date,
           c._fld693::numeric AS term_days,
           nullif(encode(c._fld694rref, 'hex'), repeat('0', 32)) AS source_stage_id,
           nullif(encode(c._fld668rref, 'hex'), repeat('0', 32)) AS purchase_type_id,
           nullif(encode(c._fld667rref, 'hex'), repeat('0', 32)) AS membership_kind_id,
           nullif(encode(c._fld697rref, 'hex'), repeat('0', 32)) AS club_access_type_id,
           nullif(encode(c._fld699rref, 'hex'), repeat('0', 32)) AS payment_type_id,
           c._description::text AS contract_name,
           contract_type._enumorder AS contract_type_order,
           club._description::text AS access_club_name,
           CASE
             WHEN c._fld694rref = decode('bc06e4c0f4cf55cd11e9e458f5b23468','hex') THEN 'NEW'
             WHEN c._fld694rref = decode('9e369c6e943d7b9e11ea0afee63d256a','hex') THEN 'EX'
             WHEN c._fld694rref = decode('91e459f1a0cf92b311e9ee9b86e33a00','hex') THEN 'RENEW'
           END AS source_stage,
           CASE WHEN c._fld699rref = decode('9bd3ea4748457ee94b2011de6d9687d7','hex')
                  THEN 'Рекарринг' ELSE 'Предоплата' END AS payment_type,
           CASE WHEN c._fld668rref = decode('b7662b4f1f13a3b2473a62cd6de3d984','hex') THEN 'Передача'
                WHEN c._fld668rref = decode('9080ed050d7309f442e5d29c209d285f','hex') THEN 'Продажа'
           END AS purchase_type,
           CASE WHEN c._fld667rref = decode('807731f355b2cf014f5a7d21a0a8c928','hex') THEN 'Подарок'
                WHEN c._fld667rref = decode('9b1f53916df347e64f2c4115a9917898','hex') THEN 'Семейный'
                WHEN c._fld667rref = decode('83115ce5e4c813f3425c99a00f3f44b7','hex') THEN 'Стандартный'
                WHEN c._fld667rref = decode('a3f5f266957fcc5244a9c8c59b6344e0','hex') THEN 'Exclusive'
                WHEN c._fld667rref = decode('aa6a6b1d54c2fa164a04c7f4428a2efe','hex') THEN 'Подарок Exclusive'
                WHEN p._description::text ILIKE '%семейн%' THEN 'Семейный'
           END AS membership_kind,
           CASE WHEN p._description::text ILIKE '%дневн%' THEN 'Дневной Физкульт'
                WHEN at.access_time IS NOT NULL AND at.access_time <> '' THEN at.access_time
                ELSE 'Безлимитный' END AS access_time_type,
           CASE WHEN p._description::text ILIKE '%сеть%' THEN 'Сетевой'
                WHEN c._fld697rref = decode('abf82ac2a7cb5ed04be0f28e6fe07689','hex') THEN 'Сетевой'
                WHEN c._fld697rref = decode('ac64dcb94a278ff64f8f05b6aa470169','hex') THEN 'Локальный'
                ELSE 'Отсутствует' END AS club_access_type,
           CASE WHEN p._fld1741rref = decode('80d300505681013811e4d85d67cfb97d','hex') THEN 'Дети'
                WHEN p._fld1741rref = decode('80d300505681013811e4d85d6e92a534','hex') THEN 'Юниоры'
                ELSE 'Взрослые' END AS base_age_category
    FROM public._reference59 c
    JOIN scoped_contract_refs scope ON scope.contract_ref=c._idrref
    LEFT JOIN public._reference163 p ON p._idrref = c._fld685rref
    LEFT JOIN public._reference132 club ON club._idrref = c._fld687rref
    LEFT JOIN public._enum495 contract_type ON contract_type._idrref=c._fld696rref
    LEFT JOIN access_time_by_product at ON at.product_ref=c._fld685rref
),
advance_seed AS (
    SELECT a._period::date AS receipt_date,
           a._recordkind::smallint AS movement_kind,
           a._recordertref, a._recorderrref, a._lineno,
           cb.*, x._description::text AS analytics_text,
           CASE
             WHEN a._recordertref=decode('0000013d','hex') THEN 'transfer'
             WHEN a._recordertref=decode('0000013c','hex') THEN 'transfer_contract'
             WHEN a._recordertref=decode('0000011d','hex') THEN 'return'
             WHEN a._recordertref=decode('00000130','hex') THEN 'card'
             WHEN a._recordertref=decode('0000015a','hex') THEN 'cash_receipt'
             WHEN a._recordertref=decode('00000147','hex') THEN 'cashless'
             WHEN a._recordertref=decode('0000013b','hex') THEN 'sales_report'
             WHEN a._recordertref=decode('0000014b','hex') THEN 'pko'
             WHEN a._recordertref=decode('00000131','hex') THEN 'certificate'
             WHEN a._recordertref=decode('0000014d','hex') THEN 'rko'
             WHEN a._recordertref=decode('00000153','hex') THEN 'advance_writeoff'
             WHEN a._recordertref=decode('00000154','hex') THEN 'cashless_writeoff'
             WHEN a._recordertref=decode('00000128','hex') THEN 'recurring_correction'
           END AS recorder_type,
           CASE WHEN a._recordertref=decode('00000147','hex')
                THEN (SELECT d._fld4235rref FROM public._document327 d WHERE d._idrref=a._recorderrref) END AS instalment_ref,
           CASE a._recordertref
                WHEN decode('00000130','hex') THEN (SELECT d._fld3680rref FROM public._document304 d WHERE d._idrref=a._recorderrref)
                WHEN decode('0000015a','hex') THEN (SELECT d._fld4891rref FROM public._document346 d WHERE d._idrref=a._recorderrref)
                WHEN decode('00000131','hex') THEN (SELECT d._fld3712rref FROM public._document305 d WHERE d._idrref=a._recorderrref)
                WHEN decode('00000153','hex') THEN (SELECT d._fld4702rref FROM public._document339 d WHERE d._idrref=a._recorderrref)
                WHEN decode('0000014b','hex') THEN (SELECT d._fld4395rref FROM public._document331 d WHERE d._idrref=a._recorderrref)
           END AS source_channel_ref,
           CASE WHEN a._recordkind=1 AND a._recordertref=ANY(ARRAY[decode('0000013c','hex'),decode('0000014d','hex'),decode('00000154','hex'),decode('0000013b','hex'),decode('00000130','hex')]) THEN -a._fld7377::numeric
                WHEN a._recordkind=1 AND a._recordertref=decode('0000014b','hex') THEN 0::numeric
                ELSE a._fld7377::numeric END AS amount_signed,
           a._fld7377::numeric AS amount_raw,
           nullif(encode(a._fld7372rref, 'hex'), repeat('0', 32)) AS movement_club_id
    FROM public._accumrg7370 a
    JOIN contract_base cb ON cb.contract_ref=a._fld7371rref
    LEFT JOIN public._reference134 x ON x._idrref=a._fld7376rref
    WHERE a._period >= $1::date AND a._period < $2::date
      AND a._recordertref=ANY(ARRAY[decode('0000013d','hex'),decode('0000013c','hex'),decode('0000011d','hex'),decode('00000130','hex'),decode('0000015a','hex'),decode('00000147','hex'),decode('0000013b','hex'),decode('0000014b','hex'),decode('00000131','hex'),decode('0000014d','hex'),decode('00000153','hex'),decode('00000154','hex'),decode('00000128','hex')])
),
advance_rows AS (
    SELECT s.*,
           CASE WHEN s.instalment_ref IS NOT NULL AND s.instalment_ref <> (SELECT zero_ref FROM constants) THEN 'instalment'
                ELSE CASE s.source_channel_ref
                     WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f','hex') THEN 'club'
                     WHEN decode('99ad9b75dc73f34911eed62832d12269','hex') THEN 'website'
                     WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d','hex') THEN 'app'
                     WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e','hex') THEN 'employee_app'
                     WHEN decode('99aff84c6229c6ae11eef6b58cf54f81','hex') THEN 'web_customer' END END AS source_object,
           CASE WHEN s.instalment_ref IS NOT NULL AND s.instalment_ref <> (SELECT zero_ref FROM constants) THEN 'Рассрочка'
                ELSE coalesce(CASE s.source_channel_ref
                     WHEN decode('99a9ebb169a4e2a611eebfc77dadf23f','hex') THEN 'Клуб'
                     WHEN decode('99ad9b75dc73f34911eed62832d12269','hex') THEN 'Website'
                     WHEN decode('99a9ebb169a4e2a611eebfc77dadf23d','hex') THEN 'App'
                     WHEN decode('99a9ebb169a4e2a611eebfc77dadf23e','hex') THEN 'App сотрудника'
                     WHEN decode('99aff84c6229c6ae11eef6b58cf54f81','hex') THEN 'Web customer' END, 'Клуб') END AS payment_source
    FROM advance_seed s
),
ordinary_raw AS (
    SELECT * FROM advance_rows ar
    WHERE ar.payment_type_id IS NOT NULL
      AND ar.recorder_type IS NOT NULL AND ar.recorder_type <> 'sale'
      AND ar.product_name IS NOT NULL
      AND ar.analytics_text NOT ILIKE '%ДСУ%'
      AND (ar.contract_name IS NULL OR ar.contract_name NOT ILIKE '%ИП%')
      AND ar.contract_type_order <> 0
      AND ar.product_category_ref <> decode('80d100505681013811e4d16f28bf1aab','hex')
),
towel_raw AS (
    SELECT ar.* FROM advance_rows ar
    WHERE ar.product_category_ref = decode('80d100505681013811e4d16f28bf1aab','hex')
),
co_access AS (
    SELECT a._period::date AS receipt_date, nullif(encode(a._fld7741rref,'hex'), repeat('0',32)) AS contract_id,
           sum(a._fld7749::numeric) AS co_access_amount
    FROM public._accumrg7739 a
    JOIN public._reference163 p ON p._idrref=a._fld7743rref
    JOIN public._reference59 c ON c._idrref=a._fld7741rref
    WHERE a._period >= $1::date AND a._period < $2::date
      AND a._fld7743rref <> (SELECT zero_ref FROM constants)
      AND a._recordkind=1 AND (p._description::text LIKE '%Со-д%' OR p._description::text LIKE '%со-д%')
      AND c._fld687rref IS NOT NULL
    GROUP BY 1,2
),
combined_advance AS (
    SELECT 'ordinary_advance'::text AS source_kind, ar.* FROM ordinary_raw ar
    UNION ALL
    SELECT 'towel_advance'::text AS source_kind, ar.* FROM towel_raw ar
),
contract_groups AS (
    SELECT source_kind, receipt_date, contract_id, client_key, analytics_text, payment_type,
           min(movement_kind) AS movement_kind, min(recorder_type) AS recorder_type,
           min(movement_club_id) AS movement_club_id, access_club_id, sales_point_club_id, min(manager_id) AS manager_id,
           product_id, product_name, product_freeze_days, activation_date, start_date, end_date, term_days, source_stage_id,
           min(source_stage) AS source_stage, min(payment_source) AS payment_source, min(base_age_category) AS base_age_category,
           min(purchase_type) AS purchase_type, purchase_type_id, min(membership_kind) AS membership_kind, membership_kind_id,
           min(club_access_type) AS club_access_type, club_access_type_id, min(access_time_type) AS access_time_type,
           min(access_club_name) AS access_club_name, source_object,
           sum(amount_raw) AS amount_raw, sum(amount_signed) AS amount_signed, count(*)::bigint AS source_movement_count
    FROM combined_advance u
    GROUP BY source_kind, receipt_date, contract_id, client_key, analytics_text, payment_type,
             access_club_id, sales_point_club_id, product_id, product_name, product_freeze_days,
             activation_date, start_date, end_date, term_days, source_stage_id, purchase_type_id,
             membership_kind_id, club_access_type_id, source_object
),
service_rows AS (
    SELECT 'membership_service'::text AS source_kind, a._period::date AS receipt_date,
           nullif(encode(a._recorderrref,'hex'), repeat('0',32)) AS source_group_recorder_id,
           a._lineno::integer AS source_group_line_no,
           nullif(encode(a._fld7741rref,'hex'), repeat('0',32)) AS contract_id,
           nullif(encode(c._fld681rref,'hex'), repeat('0',32)) AS client_key,
           a._recordkind::smallint AS movement_kind,
           nullif(encode(a._fld7746rref,'hex'), repeat('0',32)) AS movement_club_id,
           nullif(encode(c._fld687rref,'hex'), repeat('0',32)) AS access_club_id,
           nullif(encode(c._fld701rref,'hex'), repeat('0',32)) AS sales_point_club_id,
           coalesce(
             nullif(encode((SELECT d._fld4909rref FROM public._document346 d WHERE d._idrref=a._fld7742_rrref),'hex'), repeat('0',32)),
             nullif(encode(c._fld683rref,'hex'), repeat('0',32))
           ) AS manager_id,
           nullif(encode(a._fld7743rref,'hex'), repeat('0',32)) AS product_id,
           p._description::text AS product_name, p._fld1756::numeric AS product_freeze_days,
           c._fld670::date AS activation_date, c._fld671::date AS start_date, c._fld672::date AS end_date, c._fld693::numeric AS term_days,
           nullif(encode(c._fld694rref,'hex'), repeat('0',32)) AS source_stage_id,
           CASE WHEN c._fld694rref = decode('bc06e4c0f4cf55cd11e9e458f5b23468','hex') THEN 'NEW'
                WHEN c._fld694rref = decode('9e369c6e943d7b9e11ea0afee63d256a','hex') THEN 'EX'
                WHEN c._fld694rref = decode('91e459f1a0cf92b311e9ee9b86e33a00','hex') THEN 'RENEW' END AS source_stage,
           CASE WHEN p._description::text LIKE '%Со-д%' OR p._description::text LIKE '%со-д%' THEN 'Со-доступ'
                WHEN p._description::text LIKE '%Полоте%' OR p._description::text LIKE '%полоте%' THEN 'Полотенца'
                WHEN p._description::text LIKE '%Госте%' OR p._description::text LIKE '%гостев%' OR p._description::text LIKE '%день здоровья%' THEN 'Гостевой визит'
                WHEN p._description::text LIKE '%Заморо%' OR p._description::text LIKE '%заморо%' THEN 'Заморозка'
                WHEN p._description::text LIKE '%Переоформление%' THEN 'Переоформление'
                WHEN p._description::text LIKE '%Адаптац%' THEN 'Адаптация ДРЦ'
                WHEN p._description::text LIKE '%Вход для детей%' THEN 'Вход для детей' END AS service_group,
           a._fld7749::numeric AS amount_raw, a._fld7749::numeric AS amount_signed
    FROM public._accumrg7739 a
    LEFT JOIN public._reference163 p ON p._idrref=a._fld7743rref
    LEFT JOIN public._reference59 c ON c._idrref=a._fld7741rref
    WHERE a._period >= $1::date AND a._period < $2::date
      AND a._fld7743rref <> (SELECT zero_ref FROM constants) AND a._recordkind=1
      AND p._description::text NOT IN ('Полотенце','Аренда полотенца (разовая)')
),
movement AS (
    SELECT cg.source_kind, cg.source_object, NULL::text AS source_group_recorder_id, NULL::integer AS source_group_line_no,
           cg.receipt_date, cg.contract_id, cg.client_key, cg.analytics_text,
           CASE WHEN cg.payment_type='Рекарринг' THEN NULLIF(regexp_replace(cg.analytics_text, '^.*; ', ''), '')::integer END AS payment_period,
           cg.payment_type, cg.movement_kind, cg.recorder_type, cg.movement_club_id, cg.access_club_id, cg.sales_point_club_id,
           cg.access_club_id AS reporting_club_id, cg.manager_id, cg.product_id, cg.product_name, cg.product_freeze_days,
           cg.activation_date, cg.start_date, cg.end_date, cg.term_days, cg.source_stage_id, cg.source_stage,
           CASE WHEN cg.product_name ILIKE '%web%' THEN 'Web customer' ELSE cg.payment_source END AS payment_source,
           CASE WHEN cg.product_name ILIKE '%детские секции%' THEN 'Дети' ELSE cg.base_age_category END AS product_age_category,
           cg.purchase_type, cg.purchase_type_id, cg.membership_kind, cg.membership_kind_id, cg.club_access_type, cg.club_access_type_id,
           cg.access_time_type,
           CASE WHEN cg.access_club_name='Пушкинский VIP' THEN CASE WHEN cg.product_name ILIKE '%кандидат%' THEN 'VIP кандидат' WHEN cg.product_name ILIKE '%Exclusive 2%' OR cg.product_name ILIKE '%Exclusive II%' THEN 'Exclusive II' WHEN cg.product_name ILIKE '%Exclusive%' THEN 'Exclusive' ELSE 'VIP' END ELSE 'Весь клуб' END AS access_zone,
           cg.amount_raw, cg.amount_signed, coalesce(ca.co_access_amount,0)::numeric AS co_access_amount,
           (cg.amount_signed-coalesce(ca.co_access_amount,0))::numeric AS receipt_amount_net,
           NULL::text AS service_group, cg.source_movement_count,
           CASE WHEN cg.access_club_name='Пушкинский VIP' THEN 'П'
                WHEN cg.access_club_name IN ('УК','ДРЦ') THEN 'УК' ELSE 'Ф' END AS calculation_mode
    FROM contract_groups cg LEFT JOIN co_access ca USING(receipt_date,contract_id)
    UNION ALL
    SELECT s.source_kind, NULL::text, s.source_group_recorder_id, s.source_group_line_no, s.receipt_date, s.contract_id, s.client_key, NULL,
           NULL, 'Услуга', s.movement_kind, NULL, s.movement_club_id, s.access_club_id, s.sales_point_club_id,
           CASE WHEN s.service_group='Со-доступ' THEN s.access_club_id ELSE s.movement_club_id END,
           s.manager_id, s.product_id, s.product_name, s.product_freeze_days, s.activation_date, s.start_date, s.end_date, s.term_days,
           s.source_stage_id, s.source_stage, 'Клуб', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
           NULL, 'Весь клуб', s.amount_raw, s.amount_signed, 0::numeric, s.amount_signed, s.service_group, 1::bigint, 'Ф'::text
    FROM service_rows s
    WHERE s.service_group IS NOT NULL
      AND (CASE WHEN s.service_group='Со-доступ' THEN s.access_club_id ELSE s.movement_club_id END) IS NOT NULL
),
movement_enriched AS (
    SELECT m.*, CASE
      WHEN m.payment_type='Услуга' THEN 'Клип-карты'
      WHEN m.payment_type='Рекарринг' THEN CASE WHEN right(coalesce(m.analytics_text,''),2)=' 1' THEN 'Продажа' ELSE 'Списание' END
      WHEN m.source_stage IS NULL OR m.source_stage='NEW' THEN 'NEW'
      ELSE m.source_stage END AS super_stage
    FROM movement m
)
SELECT 'movement'::text AS row_type,
       source_kind, source_object, NULL::text AS kpi_unit_key, NULL::text AS kpi_unit_kind, NULL::date AS metric_date,
       receipt_date, source_group_recorder_id, source_group_line_no, contract_id, client_key, analytics_text, payment_period, payment_type,
       movement_kind, recorder_type, movement_club_id, access_club_id, sales_point_club_id, reporting_club_id, manager_id, product_id,
       product_name AS source_product_name, product_freeze_days AS source_product_freeze_days, activation_date AS contract_activation_date, start_date AS contract_start_date,
       end_date AS contract_end_date, term_days AS contract_term_days, source_stage_id, source_stage, super_stage, payment_source, product_age_category, purchase_type,
       purchase_type_id, membership_kind, membership_kind_id, club_access_type, club_access_type_id, access_time_type, access_zone,
       amount_raw, amount_signed, co_access_amount, receipt_amount_net, service_group, source_movement_count,
       NULL::numeric AS free_freeze_before_activation_days, NULL::numeric AS effective_duration_days,
       NULL::numeric AS list_contract_price, NULL::numeric AS calculation_price,
       calculation_mode
FROM movement_enriched;
