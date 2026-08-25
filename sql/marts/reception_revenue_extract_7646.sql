-- Exact current-M reception scope, AccumRg7646 branch.
-- The loader binds $1/$2 to the BR-003 horizon in one repeatable-read source snapshot.
SELECT
    '7646'::text AS source_kind,
    encode(r._recorderrref, 'hex') AS recorder_id,
    r._lineno::integer AS line_no,
    r._period::date AS service_date,
    encode(r._fld7653rref, 'hex') AS club_id,
    NULL::text AS client_key,
    NULL::text AS client_code,
    encode(r._fld7652rref, 'hex') AS employee_id,
    CAST(e._description AS varchar(1000)) AS employee_name,
    encode(r._fld7649rref, 'hex') AS service_id,
    CAST(s._fld1761 AS varchar(1000)) AS service_name,
    encode(s._fld1733rref, 'hex') AS activity_id,
    CAST(a._description AS varchar(1000)) AS activity_name,
    NULL::text AS training_format_id,
    NULL::text AS training_format_name,
    NULL::text AS calculation_category,
    NULL::text AS age_category,
    r._fld7657::numeric(15, 3) AS service_quantity,
    r._fld7659::numeric(15, 2) AS revenue_amount,
    'reception'::text AS revenue_scope,
    CASE
        WHEN CAST(s._fld1761 AS varchar(1000)) LIKE '%Соляная пещера%'
          OR CAST(s._fld1761 AS varchar(1000)) LIKE '%соляной пещеры%'
            THEN 'Соляная пещера'
        WHEN CAST(s._fld1761 AS varchar(1000)) LIKE '%ущерба%'
            THEN 'Возмещение ущерба'
        WHEN CAST(s._fld1761 AS varchar(1000)) LIKE '%Солярий%'
          OR CAST(s._fld1761 AS varchar(1000)) LIKE '%солярий%'
            THEN 'Солярий'
        WHEN CAST(s._fld1761 AS varchar(1000)) LIKE '%Аренда замка%'
          OR CAST(s._fld1761 AS varchar(1000)) LIKE '%аренда замка%'
            THEN 'Аренда замка'
        WHEN CAST(a._description AS varchar(1000)) = 'Аренда полотенец и халатов'
            THEN 'Аренда полотенец и халатов'
        WHEN CAST(a._description AS varchar(1000)) = 'Аренда шкафчиков'
            THEN 'Аренда шкафчиков'
        WHEN CAST(a._description AS varchar(1000)) = 'Товары рецепции'
            THEN 'Товары рецепции'
        ELSE 'Другое'
    END AS reception_category_key
FROM public._accumrg7646 r
JOIN public._reference163 s ON s._idrref = r._fld7649rref
LEFT JOIN public._reference70 a ON a._idrref = s._fld1733rref
LEFT JOIN public._reference225 e ON e._idrref = r._fld7652rref
WHERE r._period >= $1::date
  AND r._period < $2::date
  AND r._fld7659 IS NOT NULL
  AND r._fld7659 <> 0
  AND s._fld1795rref NOT IN (
      '\x9f007d77d46892dc47058346701d3bb6'::bytea,
      '\x89de5e634e304b1a44efac5ab7088373'::bytea,
      '\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea
  )
  AND COALESCE(a._fld843rref, '\x00'::bytea) NOT IN (
      '\x9e10e872e49a551b4968a66b95c28905'::bytea,
      '\xac626c95655c992a471b27ca8f8812cd'::bytea
  )
  AND COALESCE(CAST(s._description AS varchar(1000)), '') <> 'посещение клуба'
  AND COALESCE(CAST(a._description AS varchar(1000)), '') NOT IN (
      'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
      'Детский клуб', 'Водные программы', 'Групповые программы',
      'Тренажёрный зал', 'Тренажерный зал', 'Бар', 'Прочие услуги SPA',
      'ДРЦ Умный малыш', 'Услуги прачечной', 'Прочие виды деятельности'
  );
