-- PBI-equivalent source extract for mart.promo_application.
-- Source: Pbit_old/Отчет по промокодам.pbit (SHA-256 79005ec09a6698887b7e341d5b2b16a902fdce7b78e992888bf2e0129a409956).
-- Parameters: $1 inclusive date; $2 exclusive date. Preserves PBI-M branch aggregation and multiplicity.
-- report_row_id is a full-snapshot technical ordinal, not a durable source business key.
+-- PBI-equivalent performance candidate; no tie-break or deduplication.
WITH gift_base AS (
    SELECT 
        ar._Period::date AS period,
        cl._Code::TEXT AS client_code,
        cl._Description::TEXT AS client_name,
        encode(_Reference59._Fld694RRef, 'hex') AS stage_ref,
        main._Description::TEXT AS discount_name,
encode(main._IDRRef, 'hex') as discount_name_hex, 
        promo._Description::TEXT AS promo_code,
        COALESCE(SN._Description::TEXT, 'Без серийного номера')::TEXT AS serial_number,
        _Reference59._Code::TEXT AS subscription_code,
        _Reference59._IDRRef AS subscription_id,
        _Reference132._Description::TEXT AS club_name,
        _Reference187._Description::TEXT AS gift_name,
        present._Fld7559_RRRef AS gift_ref,
        ex_pr._Fld681RRef AS friend_id,
        ex_pr._Fld670 AS friend_activation_date,
        ex_pr._IDRRef AS friend_subscription_id,
        ex_pr._code AS present_code,
        nomen._description as nomen_description,
        encode(_Reference70._Fld843RRef, 'hex') AS business_dir_ref,
        encode(main._Fld2439RRef, 'hex') AS discount_method_ref
    FROM _AccumRg7606 ar
    LEFT JOIN _Reference59 ON _Reference59._IDRRef = ar._Fld7610RRef
    LEFT JOIN _Reference141X1 cl ON cl._IDRRef = ar._Fld7607RRef
    LEFT JOIN _Reference132 ON _Reference132._IDRRef = ar._Fld7612RRef
    LEFT JOIN _Reference163 nomen ON nomen._IDRRef = ar._Fld7611RRef
    LEFT JOIN _Reference70 ON _Reference70._IDRRef = nomen._Fld1733RRef
    LEFT JOIN _Reference135 key_disc ON key_disc._IDRRef = ar._Fld7608RRef
    LEFT JOIN _Reference220 main ON main._IDRRef = key_disc._Fld1456RRef
    LEFT JOIN _Reference163 promo ON promo._IDRRef = key_disc._Fld1457RRef
    LEFT JOIN _Reference218 SN ON SN._IDRRef = key_disc._Fld1458RRef
    INNER JOIN _AccumRg7553 present ON 
        present._Fld7554RRef = ar._Fld7610RRef
        AND present._Fld7555RRef = key_disc._Fld1456RRef
        AND present._RecordKind = 1
        AND present._Period::date >= '2025-01-01'
    LEFT JOIN _Reference187 ON _Reference187._IDRRef = present._Fld7557RRef
    LEFT JOIN _Reference59 ex_pr ON ex_pr._IDRRef = present._Fld7559_RRRef
    WHERE 
        ar._RecordKind = 1 
        AND ar._Fld7613 = 1
        AND promo._Description IS NOT NULL
        AND _Reference187._Description IS NOT NULL
        AND (_Reference59._Fld670 IS NOT NULL AND _Reference59._Fld670 <> '01.01.0001')
        AND _Reference59._Fld672 > _Reference59._Fld671
        AND ar._Period >= $1::date
        AND ar._Period < $2::date
    -- LIMIT 1000
),
discount_base AS (
    SELECT 
        ar._Period::date AS period,
        cl._Code::TEXT AS client_code,
        cl._Description::TEXT AS client_name,
        main._Description::TEXT AS discount_name,
encode(main._IDRRef, 'hex') as discount_name_hex, 
        COALESCE(sn._Description::TEXT, 'Без серийного номера')::TEXT AS serial_number,
        encode(ar._Fld7617_RRRef, 'hex')::TEXT AS sale_document_id,
        nomen._description::TEXT AS nomenklatura,
        encode(dir._Fld843RRef, 'hex') AS business_dir_ref,
        _Reference132._Description::TEXT AS club_name,
        encode(_Reference59._Fld694RRef, 'hex') AS stage_ref,
        _Reference59._Code::TEXT AS subscription_code,
        _Reference59._IDRRef AS subscription_id,
        promo._Description::TEXT AS promo_code,
        encode(main._Fld2439RRef, 'hex') AS discount_method_ref,
        max(
        ar._Fld7626
        ) 
        AS total_discount,
        sum(COALESCE(
            _Document332_VT4465._Fld4493 * _Document332_VT4465._Fld4475 ,
            _Document346_VT4924._Fld4945 * _Document346_VT4924._Fld4930
        )) AS price_without_discount,
              
        client_status.ВидСтажа AS client_stage_hex
    FROM _AccumRg7615 ar
    LEFT JOIN _Reference59 ON _Reference59._IDRRef = ar._Fld7621RRef
     AND _Reference59._Fld672 > _Reference59._Fld671
     AND _Reference59._Fld672 IS NOT NULL
     AND _Reference59._Fld671 IS NOT NULL
     AND _Reference59._Fld671 <> '0001-01-01'::date
    LEFT JOIN _Reference132 ON _Reference132._IDRRef = ar._Fld7616RRef
    LEFT JOIN _Reference141X1 cl ON cl._IDRRef = ar._Fld7618RRef
    LEFT JOIN _Reference163 nomen ON nomen._IDRRef = ar._Fld7619RRef
    LEFT JOIN _Reference163 promo ON promo._IDRRef = ar._Fld7623RRef
    LEFT JOIN _Reference220 main ON main._IDRRef = ar._Fld7620RRef AND main._IDRRef IS NOT NULL
    LEFT JOIN _Document332 ON _Document332._IDRRef = ar._Fld7617_RRRef
    LEFT JOIN _Document332_VT4465 ON 
        _Document332_VT4465._Document332_IDRRef = _Document332._IDRRef 
        AND _Document332_VT4465._Fld4467RRef = ar._Fld7621RRef
    --    AND _Document332_VT4465._LineNo4466 = ar._LineNo

    LEFT JOIN _Document346 ON _Document346._IDRRef = ar._Fld7617_RRRef

    LEFT JOIN _Document346_VT4996 ON 
        _Document346_VT4996._document346_idrref = _Document346._IDRRef
        AND _Document346_VT4996._Fld5003RRef = ar._Fld7620RRef
        AND _Document346_VT4996._Fld5001RRef = ar._Fld7623RRef
        AND _Document346_VT4996._Fld5000RRef = ar._Fld7619RRef
        and _Document346_VT4996._LineNo4997 = ar._LineNo

LEFT JOIN _Document346_VT4924 ON 
        _Document346_VT4924._document346_idrref = _Document346._IDRRef
        AND _Document346_VT4924._Fld4932RRef = ar._Fld7619RRef
        AND _Document346_VT4924._LineNo4925 = ar._LineNo

    LEFT JOIN _Reference70 dir ON dir._IDRRef = nomen._Fld1733RRef 
    LEFT JOIN _Reference218 sn ON sn._IDRRef = ar._Fld7624RRef 
    LEFT JOIN LATERAL (
        SELECT encode(ir._Fld5656RRef, 'hex') AS ВидСтажа
        FROM _InfoRg5654 ir
        WHERE ir._Fld5655RRef = ar._Fld7618RRef
          AND ir._Period < ar._Period
        ORDER BY ir._Period DESC
        LIMIT 1
    ) client_status ON true
    WHERE ar._Period >= $1::date
      AND ar._Period < $2::date
      AND promo._Description IS NOT NULL
      AND (
    _Reference59._Code IS NULL  -- Если нет ссылки на абонемент, строка остается ✅
    OR (
      _Reference59._Fld672 > _Reference59._Fld671
      AND _Reference59._Fld672 IS NOT NULL
      AND _Reference59._Fld671 IS NOT NULL
      AND _Reference59._Fld671 <> '0001-01-01'::date
    )
  )


    GROUP BY 
        ar._Period::date,
        cl._Code::TEXT,
        cl._Description::TEXT,
        main._Description::TEXT,
    encode(main._IDRRef, 'hex'),
        COALESCE(sn._Description::TEXT, 'Без серийного номера')::TEXT,
        encode(ar._Fld7617_RRRef, 'hex')::TEXT,
        nomen._description::TEXT,
        encode(dir._Fld843RRef, 'hex'),
        _Reference132._Description::TEXT,
        encode(_Reference59._Fld694RRef, 'hex'),
        _Reference59._Code::TEXT,
        _Reference59._IDRRef,
        promo._Description::TEXT,
        encode(main._Fld2439RRef, 'hex'),
        client_status.ВидСтажа
    HAVING SUM(ar._Fld7626) <> 0
),
activations_gift AS MATERIALIZED (
 SELECT cl._code::text AS client_code, r._fld681rref AS client_id, r._fld670 AS activation_date, r._idrref AS subscription_id
 FROM _reference59 r JOIN _reference141x1 cl ON cl._idrref=r._fld681rref
 WHERE r._fld670 >= $1::date AND r._fld670 < ($2::date + interval '45 days')
   AND r._fld670 <> timestamp '0001-01-01' AND r._fld672 > r._fld671
   AND encode(r._fld696rref,'hex') <> '9b656ee141a764e44de79e83cd30c1b2'
   AND encode(r._fld699rref,'hex') NOT IN ('96976725cebf51f7461429d74d3f6cbe')
   AND r._description::text NOT LIKE '%ИП%' AND r._description::text NOT LIKE '%сотрудн%'
   AND extract(day FROM r._fld672-r._fld671)>=30
),
activations_discount AS MATERIALIZED (
 SELECT cl._code::text AS client_code, r._fld670 AS activation_date, r._idrref AS subscription_id
 FROM _reference59 r JOIN _reference141x1 cl ON cl._idrref=r._fld681rref
 WHERE r._fld670 >= $1::date AND r._fld670 < ($2::date + interval '45 days')
   AND r._fld670 <> timestamp '0001-01-01' AND r._fld672 > r._fld671
   AND encode(r._fld696rref,'hex') <> '9b656ee141a764e44de79e83cd30c1b2'
   AND encode(r._fld699rref,'hex') NOT IN ('96976725cebf51f7461429d74d3f6cbe','9bd3ea4748457ee94b2011de6d9687d7')
   AND r._description::text NOT LIKE '%ИП%' AND r._description::text NOT LIKE '%сотрудн%'
   AND extract(day FROM r._fld672-r._fld671)>=30
),
dpfu AS MATERIALIZED (
 SELECT cl._code::text AS client_code, a._period AS purchase_date
 FROM (SELECT _period,_fld7576rref AS client_ref,_fld7579rref AS nomen_ref FROM _accumrg7575 WHERE _period >= $1::date AND _period < ($2::date + interval '45 days')
       UNION ALL SELECT _period,_fld7648rref,_fld7649rref FROM _accumrg7646 WHERE _period >= $1::date AND _period < ($2::date + interval '45 days')) a
 JOIN _reference141x1 cl ON cl._idrref=a.client_ref JOIN _reference163 n ON n._idrref=a.nomen_ref JOIN _reference70 d ON d._idrref=n._fld1733rref
 WHERE n._description::text IS DISTINCT FROM 'посещение клуба' AND d._description::text IN ('Игровой зал','Восстановительный фитнес','Боевые искусства','Детский клуб','Водные программы','Групповые программы','Тренажёрный зал','Тренажерный зал')
),
gift_subscription AS MATERIALIZED (SELECT DISTINCT b.client_code,b.period FROM gift_base b JOIN activations_gift a ON a.client_code=b.client_code WHERE a.activation_date>b.period::timestamp AND a.activation_date<(b.period+interval '45 days')::timestamp AND a.subscription_id<>b.subscription_id),
gift_dpfu AS MATERIALIZED (SELECT DISTINCT b.client_code,b.period FROM gift_base b JOIN dpfu d ON d.client_code=b.client_code WHERE d.purchase_date>b.period::timestamp AND d.purchase_date<(b.period+interval '45 days')::timestamp),
gift_friend AS MATERIALIZED (SELECT DISTINCT b.client_code,b.period FROM gift_base b JOIN activations_gift a ON a.client_id=b.friend_id WHERE b.gift_ref IS NOT NULL AND a.activation_date>b.friend_activation_date AND a.activation_date<(b.friend_activation_date+interval '45 days')::timestamp AND a.subscription_id<>b.friend_subscription_id),
discount_subscription AS MATERIALIZED (SELECT DISTINCT b.client_code,b.period FROM discount_base b JOIN activations_discount a ON a.client_code=b.client_code WHERE a.activation_date>b.period::timestamp AND a.activation_date<(b.period+interval '45 days')::timestamp AND a.subscription_id<>b.subscription_id),
discount_dpfu AS MATERIALIZED (SELECT DISTINCT b.client_code,b.period FROM discount_base b JOIN dpfu d ON d.client_code=b.client_code WHERE d.purchase_date>b.period::timestamp AND d.purchase_date<(b.period+interval '45 days')::timestamp),
legacy_rows AS (
 SELECT 'promo_gift'::text source_kind,b.period::date application_date,b.client_code::text client_key,b.club_name::text club_name,b.subscription_code::text membership_code,b.promo_code::text promo_name,b.serial_number::text serial_name,b.discount_name::text discount_name,b.discount_name_hex::text discount_id,
 CASE b.discount_method_ref WHEN 'b6b01903709501b44c5645e9c77486a9' THEN 'Процентом' WHEN 'a79bf47340545c104f72d7fe09065c99' THEN 'Подарком' WHEN '94ef46983e23eb214e4cc9bd42692ea9' THEN 'Подарок на выбор' WHEN 'a1c2de56711c551c4ebe151f32cdf262' THEN '% оплаты бонусами' WHEN '9ca16b48d6519697434bde9bfcaef910' THEN 'Суммой' WHEN 'b9aae3c62eea129f426dda4e0ce312de' THEN 'Суммой на документ' ELSE '' END::text discount_method,b.nomen_description::text service_name,
 CASE b.business_dir_ref WHEN '88e0831aedad96f548a7b27ca573f887' THEN 'ДСУ' WHEN '9e10e872e49a551b4968a66b95c28905' THEN 'Прочие членство' WHEN '970416c57456fcbf4552083459077b03' THEN 'Бар' WHEN '8daa0eaeb39e6f50420feeaf8b9b1983' THEN 'Комиссия' WHEN 'bdbb8cff6a538a4742b1b8fcf27c6ae2' THEN 'Прочие услуги' WHEN 'a70c9409366237d041ea42341405ed8d' THEN 'СПА' WHEN 'ac626c95655c992a471b27ca8f8812cd' THEN 'Членство' END::text business_direction,b.gift_name::text gift_name,b.present_code::text gift_recipient_membership_code,
 CASE b.stage_ref WHEN 'bc06e4b21430ebfb44a67a65c46d41f9' THEN 'NEW' WHEN '9e369ac955bf602149e17b549b0f1498' THEN 'EX' WHEN '91e4594e35ce15d847c4a3f32e1e18f2' THEN 'RENEW' ELSE 'Не определено' END::text client_stage,NULL::numeric discount_amount,NULL::numeric price_before_discount,(s.client_code IS NOT NULL) bought_membership_45d_flag,(d.client_code IS NOT NULL) bought_dpfu_45d_flag,CASE WHEN b.gift_ref IS NULL THEN NULL ELSE f.client_code IS NOT NULL END friend_bought_membership_45d_flag
 FROM gift_base b LEFT JOIN gift_subscription s ON s.client_code=b.client_code AND s.period=b.period LEFT JOIN gift_dpfu d ON d.client_code=b.client_code AND d.period=b.period LEFT JOIN gift_friend f ON f.client_code=b.client_code AND f.period=b.period
 UNION ALL
 SELECT 'discount',b.period::date,b.client_code::text,b.club_name::text,b.subscription_code::text,b.promo_code::text,b.serial_number::text,b.discount_name::text,b.discount_name_hex::text,
 CASE b.discount_method_ref WHEN 'b6b01903709501b44c5645e9c77486a9' THEN 'Процентом' WHEN 'a79bf47340545c104f72d7fe09065c99' THEN 'Подарком' WHEN '94ef46983e23eb214e4cc9bd42692ea9' THEN 'Подарок на выбор' WHEN 'a1c2de56711c551c4ebe151f32cdf262' THEN '% оплаты бонусами' WHEN '9ca16b48d6519697434bde9bfcaef910' THEN 'Суммой' WHEN 'b9aae3c62eea129f426dda4e0ce312de' THEN 'Суммой на документ' ELSE '' END::text,b.nomenklatura::text,
 CASE b.business_dir_ref WHEN '88e0831aedad96f548a7b27ca573f887' THEN 'ДСУ' WHEN '9e10e872e49a551b4968a66b95c28905' THEN 'Прочие членство' WHEN '970416c57456fcbf4552083459077b03' THEN 'Бар' WHEN '8daa0eaeb39e6f50420feeaf8b9b1983' THEN 'Комиссия' WHEN 'bdbb8cff6a538a4742b1b8fcf27c6ae2' THEN 'Прочие услуги' WHEN 'a70c9409366237d041ea42341405ed8d' THEN 'СПА' WHEN 'ac626c95655c992a471b27ca8f8812cd' THEN 'Членство' END::text,NULL::text,NULL::text,
 CASE b.client_stage_hex WHEN 'bc06e4b21430ebfb44a67a65c46d41f9' THEN 'NEW' WHEN '9e369ac955bf602149e17b549b0f1498' THEN 'EX' WHEN '91e4594e35ce15d847c4a3f32e1e18f2' THEN 'RENEW' ELSE 'NEW' END::text,b.total_discount::numeric,b.price_without_discount::numeric,(s.client_code IS NOT NULL),(d.client_code IS NOT NULL),NULL::boolean
 FROM discount_base b LEFT JOIN discount_subscription s ON s.client_code=b.client_code AND s.period=b.period LEFT JOIN discount_dpfu d ON d.client_code=b.client_code AND d.period=b.period
)
SELECT row_number() OVER (ORDER BY application_date, source_kind, client_key, promo_name, serial_name, membership_code, discount_id, gift_name, discount_amount, price_before_discount) AS report_row_id, * FROM legacy_rows
