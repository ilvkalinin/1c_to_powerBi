-- Read-only checks for report "Выручка ДПФУ".
-- Executed against gymdb on 2026-08-11 with
-- default_transaction_read_only=on and statement_timeout=240000.
-- Every result is a live source-side control value, not a frozen Power BI export.

-- SV-054: exact current-PBI qualification of the regular DPFU fact.
WITH qualified_dpfu AS (
    SELECT
        '7575'::text AS source_kind,
        r._period,
        r._active,
        r._recordertref,
        r._recorderrref,
        r._lineno,
        r._fld7576rref AS client_id,
        r._fld7577rref AS club_id,
        r._fld7579rref AS service_id,
        r._fld7582rref AS employee_id,
        s._fld1733rref AS activity_id,
        s._fld1803rref AS training_format_id,
        r._fld7585 AS service_quantity,
        r._fld7586 AS revenue_amount
    FROM public._accumrg7575 r
    JOIN public._reference163 s ON s._idrref = r._fld7579rref
    JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= DATE '2024-01-01' AND r._period < DATE '2027-01-01'
      AND r._fld7586 <> 0
      AND s._fld1795rref = '\\x9f007d77d46892dc47058346701d3bb6'::bytea
      AND a._fld843rref NOT IN (
          '\\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\\xac626c95655c992a471b27ca8f8812cd'::bytea
      )
      AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(a._description AS varchar(1000)) IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал'
      )

    UNION ALL

    SELECT
        '7646'::text,
        r._period,
        r._active,
        r._recordertref,
        r._recorderrref,
        r._lineno,
        r._fld7648rref,
        r._fld7653rref,
        r._fld7649rref,
        r._fld7652rref,
        s._fld1733rref,
        s._fld1803rref,
        r._fld7657,
        r._fld7659
    FROM public._accumrg7646 r
    JOIN public._reference163 s ON s._idrref = r._fld7649rref
    JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= DATE '2024-01-01' AND r._period < DATE '2027-01-01'
      AND r._fld7659 <> 0
      AND s._fld1795rref NOT IN (
          '\\x9f007d77d46892dc47058346701d3bb6'::bytea,
          '\\x89de5e634e304b1a44efac5ab7088373'::bytea,
          '\\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea
      )
      AND a._fld843rref NOT IN (
          '\\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\\xac626c95655c992a471b27ca8f8812cd'::bytea
      )
      AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(a._description AS varchar(1000)) IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал'
      )
)
SELECT
    source_kind,
    COUNT(*) AS movement_rows,
    SUM(service_quantity) AS service_quantity,
    SUM(revenue_amount) AS revenue_amount,
    COUNT(*) FILTER (WHERE NOT _active) AS inactive_rows,
    COUNT(*) FILTER (WHERE revenue_amount < 0) AS negative_rows,
    COUNT(*) - COUNT(DISTINCT (_recordertref, _recorderrref, _lineno))
        AS duplicate_technical_keys
FROM qualified_dpfu
GROUP BY source_kind
ORDER BY source_kind;

-- SV-055: current PBI IP branch, with a day-level control that preserves sum.
WITH ip AS (
    SELECT r._period, r._active, r._fld7377 AS revenue_amount,
           r._fld7372rref AS club_id, c._fld685rref AS service_id
    FROM public._accumrg7370 r
    JOIN public._reference59 c ON c._idrref = r._fld7371rref
    JOIN public._reference163 s ON s._idrref = c._fld685rref
    WHERE r._period >= DATE '2024-05-01'
      AND r._recordkind = 0
      AND CAST(s._description AS varchar(1000)) LIKE '%ИП%'
),
legacy_month AS (
    SELECT date_trunc('month', _period), club_id, service_id, SUM(revenue_amount) revenue_amount
    FROM ip GROUP BY 1, 2, 3
),
movement_day AS (
    SELECT _period::date, club_id, service_id, SUM(revenue_amount) revenue_amount
    FROM ip GROUP BY 1, 2, 3
)
SELECT
    (SELECT COUNT(*) FROM ip) AS movement_rows,
    (SELECT SUM(revenue_amount) FROM ip) AS source_sum,
    (SELECT COUNT(*) FROM legacy_month) AS legacy_month_rows,
    (SELECT COUNT(*) FROM movement_day) AS movement_day_rows,
    (SELECT SUM(revenue_amount) FROM legacy_month) -
    (SELECT SUM(revenue_amount) FROM movement_day) AS aggregation_delta;

-- SV-056: plan detail key.  Fld6617 is the client; Fld6619 is a non-client
-- technical discriminator and is required to retain all current lines.
WITH p AS (
    SELECT *
    FROM public._inforg6612
    WHERE _fld6613 >= DATE '2024-01-01' AND _fld6613 < DATE '2027-01-01'
)
SELECT
    COUNT(*) AS plan_rows,
    SUM(_fld6620) AS planned_revenue,
    COUNT(*) FILTER (WHERE NOT _active) AS inactive_rows,
    COUNT(*) - COUNT(DISTINCT (_recordertref, _recorderrref, _lineno)) AS duplicate_technical_keys,
    COUNT(*) - COUNT(DISTINCT (
        _fld6613::date, _fld6615rref, _fld6614rref, _fld6616rref, _fld6617rref
    )) AS excess_without_fld6619,
    COUNT(*) - COUNT(DISTINCT (
        _fld6613::date, _fld6615rref, _fld6614rref, _fld6616rref, _fld6617rref, _fld6619
    )) AS excess_with_fld6619
FROM p;

-- SV-057: run each query below as EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
-- using the same read-only connection. The regular fact query is the 7575
-- branch of qualified_dpfu above, grouped by day and its target dimensions.
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT r._period::date, r._fld7577rref, r._fld7576rref, r._fld7579rref,
       r._fld7582rref, s._fld1733rref, s._fld1803rref,
       SUM(r._fld7585), SUM(r._fld7586)
FROM public._accumrg7575 r
JOIN public._reference163 s ON s._idrref = r._fld7579rref
JOIN public._reference70 a ON a._idrref = s._fld1733rref
WHERE r._period >= DATE '2024-01-01' AND r._period < DATE '2027-01-01'
  AND r._fld7586 <> 0
  AND s._fld1795rref = '\\x9f007d77d46892dc47058346701d3bb6'::bytea
  AND a._fld843rref NOT IN ('\\x9e10e872e49a551b4968a66b95c28905'::bytea,
                             '\\xac626c95655c992a471b27ca8f8812cd'::bytea)
  AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
  AND CAST(a._description AS varchar(1000)) IN (
      'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
      'Детский клуб', 'Водные программы', 'Групповые программы',
      'Тренажёрный зал', 'Тренажерный зал'
  )
GROUP BY 1, 2, 3, 4, 5, 6, 7;

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT r._period::date, r._fld7372rref, c._fld685rref, SUM(r._fld7377)
FROM public._accumrg7370 r
JOIN public._reference59 c ON c._idrref = r._fld7371rref
JOIN public._reference163 s ON s._idrref = c._fld685rref
WHERE r._period >= DATE '2024-05-01'
  AND r._recordkind = 0
  AND CAST(s._description AS varchar(1000)) LIKE '%ИП%'
GROUP BY 1, 2, 3;

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT r._fld6613::date, r._fld6615rref, r._fld6614rref, r._fld6616rref,
       r._fld6617rref, r._fld6619, SUM(r._fld6620)
FROM public._inforg6612 r
WHERE r._fld6613 >= DATE '2024-01-01' AND r._fld6613 < DATE '2027-01-01'
GROUP BY 1, 2, 3, 4, 5, 6;
