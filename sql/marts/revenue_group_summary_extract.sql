-- Read-only source branches for mart.revenue_group_summary_daily.
-- The runner binds $1 = BR-003 horizon start and $2 = exclusive horizon end,
-- opens a REPEATABLE READ, READ ONLY source snapshot, and copies only this
-- four-column business projection plus the temporary control branch.
-- No permanent source-side staging object is created.

WITH membership_base AS (
    SELECT
        a._period::date AS revenue_date,
        encode(r132._idrref, 'hex') AS club_id,
        CAST(r132._description AS varchar(1000)) AS club_name,
        a._recordkind AS record_kind,
        a._fld7377::numeric(18, 2) AS revenue_amount,
        r59._fld696rref AS contract_type_id,
        CAST(r59._description AS varchar(1000)) AS contract_name,
        r163._fld1733rref AS activity_id,
        CAST(r163._description AS varchar(1000)) AS service_name,
        CAST(r134._description AS varchar(1000)) AS analytics_name,
        d316._idrref AS d316_id,
        d331._idrref AS d331_id,
        d333._idrref AS d333_id,
        d340._idrref AS d340_id,
        d315._idrref AS d315_id,
        d304._idrref AS d304_id,
        d332._idrref AS d332_id,
        d285._idrref AS d285_id,
        d346._idrref AS d346_id,
        d327._idrref AS d327_id,
        d305._idrref AS d305_id,
        d339._idrref AS d339_id,
        d296._idrref AS d296_id,
        d317._idrref AS d317_id
    FROM public._accumrg7370 a
    LEFT JOIN public._reference59 r59 ON r59._idrref = a._fld7371rref
    LEFT JOIN public._reference132 r132 ON r132._idrref = r59._fld687rref
    LEFT JOIN public._reference163 r163 ON r163._idrref = r59._fld685rref
    LEFT JOIN public._reference134 r134 ON r134._idrref = a._fld7376rref
    LEFT JOIN public._document316 d316 ON d316._idrref = a._recorderrref
    LEFT JOIN public._document331 d331 ON d331._idrref = a._recorderrref
    LEFT JOIN public._document333 d333 ON d333._idrref = a._recorderrref
    LEFT JOIN public._document340 d340 ON d340._idrref = a._recorderrref
    LEFT JOIN public._document315 d315 ON d315._idrref = a._recorderrref
    LEFT JOIN public._document304 d304 ON d304._idrref = a._recorderrref
    LEFT JOIN public._document332 d332 ON d332._idrref = a._recorderrref
    LEFT JOIN public._document285 d285 ON d285._idrref = a._recorderrref
    LEFT JOIN public._document346 d346 ON d346._idrref = a._recorderrref
    LEFT JOIN public._document327 d327 ON d327._idrref = a._recorderrref
    LEFT JOIN public._document305 d305 ON d305._idrref = a._recorderrref
    LEFT JOIN public._document339 d339 ON d339._idrref = a._recorderrref
    LEFT JOIN public._document296 d296 ON d296._idrref = a._recorderrref
    LEFT JOIN public._document317 d317 ON d317._idrref = a._recorderrref
    WHERE a._period >= $1::date
      AND a._period < $2::date
),
membership_documented AS (
    SELECT *,
           CASE
               WHEN record_kind = 1 AND d331_id IS NOT NULL THEN 0::numeric
               WHEN record_kind = 1
                AND COALESCE(d316_id, d333_id, d340_id, d315_id, d304_id) IS NOT NULL
                   THEN -revenue_amount
               ELSE revenue_amount
           END AS signed_revenue_amount,
           COALESCE(
               d316_id, d331_id, d333_id, d340_id, d315_id, d304_id,
               d285_id, d346_id, d327_id, d305_id, d339_id, d296_id, d317_id
           ) AS included_document_id
    FROM membership_base
),
membership_contract AS (
    SELECT 'membership_contract'::text AS source_branch,
           revenue_date,
           club_id,
           CASE WHEN club_name = 'Детский развивающий центр'
                THEN '06.ДРЦ' ELSE '02.ЧЛЕНСТВО' END AS revenue_article_code,
           sum(signed_revenue_amount)::numeric(18, 2) AS revenue_amount
    FROM membership_documented
    WHERE contract_type_id <> '\x9b656ee141a764e44de79e83cd30c1b2'::bytea
      AND (contract_name IS NULL OR contract_name NOT LIKE '%ИП%')
      AND COALESCE(analytics_name, '') NOT LIKE '%ДСУ%'
      AND d332_id IS NULL
      AND included_document_id IS NOT NULL
    GROUP BY revenue_date, club_id, club_name
),
membership_other AS (
    SELECT 'membership_other'::text AS source_branch,
           revenue_date,
           club_id,
           CASE WHEN club_name = 'Детский развивающий центр'
                THEN '06.ДРЦ' ELSE '02.ЧЛЕНСТВО' END AS revenue_article_code,
           sum(signed_revenue_amount)::numeric(18, 2) AS revenue_amount
    FROM membership_documented
    WHERE activity_id = '\x80d100505681013811e4d16f28bf1aab'::bytea
      AND d332_id IS NULL
      AND included_document_id IS NOT NULL
    GROUP BY revenue_date, club_id, club_name
),
membership_goods AS (
    SELECT 'membership_goods'::text AS source_branch,
           a._period::date AS revenue_date,
           encode(CASE
               WHEN CAST(r163._description AS varchar(1000)) LIKE '%Со-д%'
                 OR CAST(r163._description AS varchar(1000)) LIKE '%со-д%'
                    THEN r59_club._idrref
               ELSE r132._idrref
           END, 'hex') AS club_id,
           CASE
               WHEN CAST(r163._description AS varchar(1000)) LIKE '%Со-д%'
                 OR CAST(r163._description AS varchar(1000)) LIKE '%со-д%'
                    THEN CASE WHEN CAST(r59_club._description AS varchar(1000)) = 'Детский развивающий центр'
                              THEN '06.ДРЦ' ELSE '02.ЧЛЕНСТВО' END
               WHEN CAST(r132._description AS varchar(1000)) = 'Детский развивающий центр'
                    THEN '06.ДРЦ'
               ELSE '02.ЧЛЕНСТВО'
           END AS revenue_article_code,
           sum(a._fld7749)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7739 a
    LEFT JOIN public._reference132 r132 ON r132._idrref = a._fld7746rref
    LEFT JOIN public._reference163 r163 ON r163._idrref = a._fld7743rref
    LEFT JOIN public._reference59 r59 ON r59._idrref = a._fld7741rref
    LEFT JOIN public._reference132 r59_club ON r59_club._idrref = r59._fld687rref
    WHERE a._period >= $1::date
      AND a._period < $2::date
      AND a._recordkind = 1
      AND a._fld7743rref <> decode('00000000000000000000000000000000', 'hex')
      AND (
          CAST(r163._description AS varchar(1000)) LIKE '%Полоте%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%полоте%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%Госте%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%гостев%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%день здоровья%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%Переоформление%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%Адаптац%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%Вход для детей%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%Заморо%'
          OR CAST(r163._description AS varchar(1000)) LIKE '%заморо%'
      )
      AND CAST(r163._description AS varchar(1000)) NOT IN (
          'Полотенце', 'Аренда полотенца (разовая)'
      )
    GROUP BY a._period::date, r132._idrref, r132._description,
             r59_club._idrref, r163._description
),
dpfu_7575 AS (
    SELECT 'dpfu_7575'::text AS source_branch,
           a._period::date AS revenue_date,
           encode(r132._idrref, 'hex') AS club_id,
           '03.ДПФУ (ШТАТ)'::text AS revenue_article_code,
           sum(a._fld7586)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7575 a
    LEFT JOIN public._reference132 r132 ON r132._idrref = a._fld7577rref
    LEFT JOIN public._reference163 r163 ON r163._idrref = a._fld7579rref
    LEFT JOIN public._reference70 r70 ON r70._idrref = r163._fld1733rref
    WHERE a._period >= $1::date
      AND a._period < $2::date
      AND r163._fld1795rref = '\x9f007d77d46892dc47058346701d3bb6'::bytea
      AND r70._fld843rref NOT IN (
          '\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\xac626c95655c992a471b27ca8f8812cd'::bytea
      )
      AND CAST(r163._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(r70._description AS varchar(1000)) IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал'
      )
      AND a._fld7586 IS NOT NULL AND a._fld7586 <> 0
    GROUP BY a._period::date, r132._idrref
),
dpfu_7646 AS (
    SELECT 'dpfu_7646'::text AS source_branch,
           a._period::date AS revenue_date,
           encode(r132._idrref, 'hex') AS club_id,
           '03.ДПФУ (ШТАТ)'::text AS revenue_article_code,
           sum(a._fld7659)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7646 a
    LEFT JOIN public._reference132 r132 ON r132._idrref = a._fld7653rref
    LEFT JOIN public._reference163 r163 ON r163._idrref = a._fld7649rref
    LEFT JOIN public._reference70 r70 ON r70._idrref = r163._fld1733rref
    WHERE a._period >= $1::date
      AND a._period < $2::date
      AND r163._fld1795rref NOT IN (
          '\x9f007d77d46892dc47058346701d3bb6'::bytea,
          '\x89de5e634e304b1a44efac5ab7088373'::bytea,
          '\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea
      )
      AND r70._fld843rref NOT IN (
          '\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\xac626c95655c992a471b27ca8f8812cd'::bytea
      )
      AND CAST(r163._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(r70._description AS varchar(1000)) IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал'
      )
      AND a._fld7659 IS NOT NULL AND a._fld7659 <> 0
    GROUP BY a._period::date, r132._idrref
),
ip_revenue AS (
    SELECT 'ip_revenue'::text AS source_branch,
           a._period::date AS revenue_date,
           encode(r132._idrref, 'hex') AS club_id,
           '04.ДПФУ (АРЕНДА ИП)'::text AS revenue_article_code,
           sum(a._fld7377)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7370 a
    LEFT JOIN public._reference59 r59 ON r59._idrref = a._fld7371rref
    LEFT JOIN public._reference163 r163 ON r163._idrref = r59._fld685rref
    LEFT JOIN public._reference132 r132 ON r132._idrref = a._fld7372rref
    WHERE a._period >= $1::date
      AND a._period < $2::date
      AND CAST(r163._description AS varchar(1000)) LIKE '%ИП%'
      AND a._recordkind = 0
    GROUP BY a._period::date, r132._idrref
),
reception_7575_raw AS (
    SELECT a._period::date AS revenue_date,
           encode(r132._idrref, 'hex') AS club_id,
           sum(a._fld7586)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7575 a
    LEFT JOIN public._reference132 r132 ON r132._idrref = a._fld7577rref
    LEFT JOIN public._reference163 r163 ON r163._idrref = a._fld7579rref
    LEFT JOIN public._reference70 r70 ON r70._idrref = r163._fld1733rref
    WHERE a._period >= $1::date
      AND a._period < $2::date
      AND r163._fld1795rref IN (
          '\x9f007d77d46892dc47058346701d3bb6'::bytea,
          '\x8c807e46a4e01db54ab1c0ddf6eea237'::bytea
      )
      AND COALESCE(r70._fld843rref, '\x00'::bytea) NOT IN (
          '\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\xac626c95655c992a471b27ca8f8812cd'::bytea
      )
      AND CAST(COALESCE(r163._description, '') AS varchar(1000)) <> 'посещение клуба'
      AND CAST(COALESCE(r70._description, '') AS varchar(1000)) NOT IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал', 'Бар', 'Прочие услуги SPA',
          'ДРЦ Умный малыш', 'Услуги прачечной', 'Прочие виды деятельности'
      )
    GROUP BY a._period::date, r132._idrref
),
reception_7646_raw AS (
    SELECT a._period::date AS revenue_date,
           encode(r132._idrref, 'hex') AS club_id,
           sum(a._fld7659)::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7646 a
    LEFT JOIN public._reference132 r132 ON r132._idrref = a._fld7653rref
    LEFT JOIN public._reference163 r163 ON r163._idrref = a._fld7649rref
    LEFT JOIN public._reference70 r70 ON r70._idrref = r163._fld1733rref
    WHERE a._period >= $1::date
      AND a._period < $2::date
      AND r163._fld1795rref NOT IN (
          '\x9f007d77d46892dc47058346701d3bb6'::bytea,
          '\x89de5e634e304b1a44efac5ab7088373'::bytea,
          '\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea
      )
      AND COALESCE(r70._fld843rref, '\x00'::bytea) NOT IN (
          '\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\xac626c95655c992a471b27ca8f8812cd'::bytea
      )
      AND CAST(COALESCE(r163._description, '') AS varchar(1000)) <> 'посещение клуба'
      AND CAST(COALESCE(r70._description, '') AS varchar(1000)) NOT IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал', 'Бар', 'Прочие услуги SPA',
          'ДРЦ Умный малыш', 'Услуги прачечной', 'Прочие виды деятельности'
      )
    GROUP BY a._period::date, r132._idrref
),
reception AS (
    SELECT 'reception'::text AS source_branch,
           revenue_date,
           club_id,
           '05.РЕЦЕПЦИЯ'::text AS revenue_article_code,
           sum(revenue_amount)::numeric(18, 2) AS revenue_amount
    FROM (
        SELECT revenue_date, club_id, revenue_amount FROM reception_7575_raw
        UNION ALL
        SELECT revenue_date, club_id, revenue_amount FROM reception_7646_raw
    ) x
    GROUP BY revenue_date, club_id
    HAVING sum(revenue_amount) IS NOT NULL AND sum(revenue_amount) <> 0
),
source_branches AS (
    SELECT * FROM membership_contract
    UNION ALL SELECT * FROM membership_other
    UNION ALL SELECT * FROM membership_goods
    UNION ALL SELECT * FROM dpfu_7575
    UNION ALL SELECT * FROM dpfu_7646
    UNION ALL SELECT * FROM ip_revenue
    UNION ALL SELECT * FROM reception
)
SELECT source_branch, revenue_date, club_id, revenue_article_code, revenue_amount
FROM source_branches
WHERE club_id IS NOT NULL;
