-- Read-only reconciliation for reception initial load.
-- Run the source control in the same REPEATABLE READ source snapshot as the
-- extracts. Expected: one row for every source_kind × confirmed category;
-- source, stage and target controls must match exactly.

-- Source controls. Environment: VM-1 / gymdb / read-only snapshot.
WITH source_rows AS (
    SELECT '7575'::text AS source_kind,
           CAST(s._fld1761 AS varchar(1000)) AS service_name,
           CAST(a._description AS varchar(1000)) AS activity_name,
           r._fld7585::numeric(15, 3) AS sold_quantity,
           r._fld7586::numeric(15, 2) AS revenue_amount
    FROM public._accumrg7575 r
    LEFT JOIN public._reference163 s ON s._idrref = r._fld7579rref
    LEFT JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= $1::date
      AND r._period < $2::date
      AND r._fld7586 IS NOT NULL AND r._fld7586 <> 0
      AND s._fld1795rref IN ('\x9f007d77d46892dc47058346701d3bb6'::bytea,
                              '\x8c807e46a4e01db54ab1c0ddf6eea237'::bytea)
      AND COALESCE(a._fld843rref, '\x00'::bytea) NOT IN
          ('\x9e10e872e49a551b4968a66b95c28905'::bytea,
           '\xac626c95655c992a471b27ca8f8812cd'::bytea)
      AND COALESCE(CAST(s._description AS varchar(1000)), '') <> 'посещение клуба'
      AND COALESCE(CAST(a._description AS varchar(1000)), '') NOT IN
          ('Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
           'Детский клуб', 'Водные программы', 'Групповые программы',
           'Тренажёрный зал', 'Тренажерный зал', 'Бар', 'Прочие услуги SPA',
           'ДРЦ Умный малыш', 'Услуги прачечной', 'Прочие виды деятельности')
    UNION ALL
    SELECT '7646'::text, CAST(s._fld1761 AS varchar(1000)),
           CAST(a._description AS varchar(1000)), r._fld7657::numeric(15, 3),
           r._fld7659::numeric(15, 2)
    FROM public._accumrg7646 r
    LEFT JOIN public._reference163 s ON s._idrref = r._fld7649rref
    LEFT JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= $1::date
      AND r._period < $2::date
      AND r._fld7659 IS NOT NULL AND r._fld7659 <> 0
      AND s._fld1795rref NOT IN ('\x9f007d77d46892dc47058346701d3bb6'::bytea,
                                  '\x89de5e634e304b1a44efac5ab7088373'::bytea,
                                  '\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea)
      AND COALESCE(a._fld843rref, '\x00'::bytea) NOT IN
          ('\x9e10e872e49a551b4968a66b95c28905'::bytea,
           '\xac626c95655c992a471b27ca8f8812cd'::bytea)
      AND COALESCE(CAST(s._description AS varchar(1000)), '') <> 'посещение клуба'
      AND COALESCE(CAST(a._description AS varchar(1000)), '') NOT IN
          ('Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
           'Детский клуб', 'Водные программы', 'Групповые программы',
           'Тренажёрный зал', 'Тренажерный зал', 'Бар', 'Прочие услуги SPA',
           'ДРЦ Умный малыш', 'Услуги прачечной', 'Прочие виды деятельности')
), classified AS (
    SELECT source_kind,
           CASE
               WHEN service_name LIKE '%Соляная пещера%'
                 OR service_name LIKE '%соляной пещеры%' THEN 'Соляная пещера'
               WHEN service_name LIKE '%ущерба%' THEN 'Возмещение ущерба'
               WHEN service_name LIKE '%Солярий%'
                 OR service_name LIKE '%солярий%' THEN 'Солярий'
               WHEN service_name LIKE '%Аренда замка%'
                 OR service_name LIKE '%аренда замка%' THEN 'Аренда замка'
               WHEN activity_name = 'Аренда полотенец и халатов' THEN 'Аренда полотенец и халатов'
               WHEN activity_name = 'Аренда шкафчиков' THEN 'Аренда шкафчиков'
               WHEN activity_name = 'Товары рецепции' THEN 'Товары рецепции'
               ELSE 'Другое'
           END AS reception_category_key,
           sold_quantity, revenue_amount
    FROM source_rows
)
SELECT source_kind, reception_category_key,
       count(*)::bigint AS movement_rows,
       sum(sold_quantity)::numeric(18, 3) AS sold_quantity,
       sum(revenue_amount)::numeric(18, 2) AS revenue_amount
FROM classified
GROUP BY source_kind, reception_category_key
ORDER BY source_kind, reception_category_key;

-- Target controls. Environment: VM-2 / fitness_dwh / read-only transaction.
SELECT source_kind, reception_category_key,
       count(*)::bigint AS movement_rows,
       sum(service_quantity)::numeric(18, 3) AS sold_quantity,
       sum(revenue_amount)::numeric(18, 2) AS revenue_amount,
       count(*) - count(DISTINCT (source_kind, recorder_id, line_no)) AS duplicate_keys,
       count(*) FILTER (
           WHERE revenue_scope <> 'reception'
              OR client_key IS NOT NULL OR client_code IS NOT NULL
              OR calculation_category IS NOT NULL OR age_category IS NOT NULL
              OR employee_id IS NULL OR service_date IS NULL OR club_id IS NULL
              OR service_id IS NULL OR service_name IS NULL
              OR service_date < $1::date OR service_date >= $2::date
       ) AS contract_violations
FROM mart.ancillary_revenue_movement
WHERE revenue_scope = 'reception'
GROUP BY source_kind, reception_category_key
ORDER BY source_kind, reception_category_key;

-- DPFU preservation control. Capture before and compare after the transaction.
SELECT source_kind, count(*)::bigint AS movement_rows,
       sum(service_quantity)::numeric(18, 3) AS service_quantity,
       sum(revenue_amount)::numeric(18, 2) AS revenue_amount
FROM mart.ancillary_revenue_movement
WHERE revenue_scope = 'dpfu'
GROUP BY source_kind
ORDER BY source_kind;
