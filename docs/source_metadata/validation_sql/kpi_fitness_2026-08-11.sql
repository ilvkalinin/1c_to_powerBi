-- KPI Fitness server validation, executed 2026-08-11 through a
-- read-only PostgreSQL connection. Values are live controls, not an export.

-- SV-060: compare the legacy Renew logic with client-month presence.
-- `qualified` is the exact 7575/7646 PBIT qualification from SV-054,
-- narrowed here to the two months required for the control.
WITH qualified AS (
    SELECT r._period, r._fld7576rref AS client_id, r._fld7577rref AS club_id
    FROM public._accumrg7575 r
    JOIN public._reference163 s ON s._idrref = r._fld7579rref
    JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= DATE '2026-06-01' AND r._period < DATE '2026-08-01'
      AND r._fld7586 <> 0
      AND s._fld1795rref = '\\x9f007d77d46892dc47058346701d3bb6'::bytea
      AND a._fld843rref NOT IN (
          '\\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\\xac626c95655c992a471b27ca8f8812cd'::bytea)
      AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(a._description AS varchar(1000)) IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал')
    UNION ALL
    SELECT r._period, r._fld7648rref, r._fld7653rref
    FROM public._accumrg7646 r
    JOIN public._reference163 s ON s._idrref = r._fld7649rref
    JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= DATE '2026-06-01' AND r._period < DATE '2026-08-01'
      AND r._fld7659 <> 0
      AND s._fld1795rref NOT IN (
          '\\x9f007d77d46892dc47058346701d3bb6'::bytea,
          '\\x89de5e634e304b1a44efac5ab7088373'::bytea,
          '\\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea)
      AND a._fld843rref NOT IN (
          '\\x9e10e872e49a551b4968a66b95c28905'::bytea,
          '\\xac626c95655c992a471b27ca8f8812cd'::bytea)
      AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(a._description AS varchar(1000)) IN (
          'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы',
          'Тренажёрный зал', 'Тренажерный зал')
),
legacy AS (
    SELECT *, date_trunc('month', _period)::date AS month_start,
        LAG(_period) OVER (PARTITION BY client_id, club_id ORDER BY _period)
            AS previous_period
    FROM qualified
),
legacy_july AS (
    SELECT DISTINCT client_id, club_id
    FROM legacy
    WHERE month_start = DATE '2026-07-01'
      AND date_trunc('month', previous_period)::date = DATE '2026-06-01'
),
presence_july AS (
    SELECT DISTINCT july.client_id, july.club_id
    FROM qualified july
    WHERE july._period >= DATE '2026-07-01' AND july._period < DATE '2026-08-01'
      AND EXISTS (
          SELECT 1 FROM qualified june
          WHERE june._period >= DATE '2026-06-01' AND june._period < DATE '2026-07-01'
            AND june.client_id = july.client_id AND june.club_id = july.club_id)
)
SELECT
    (SELECT count(*) FROM legacy_july) AS legacy_renew_client_clubs,
    (SELECT count(*) FROM presence_july) AS monthly_presence_client_clubs,
    (SELECT count(*) FROM legacy_july l FULL JOIN presence_july p USING (client_id, club_id)
      WHERE l.client_id IS NULL OR p.client_id IS NULL) AS differing_client_clubs;

-- SV-061: exact monetary IP branch and its current PBIT month grain.
WITH ip AS (
    SELECT r._period, r._active, r._recordertref, r._recorderrref, r._lineno,
           r._fld7372rref AS club_id, c._fld685rref AS service_id,
           r._fld7374rref AS client_id, r._fld7377 AS revenue
    FROM public._accumrg7370 r
    JOIN public._reference59 c ON c._idrref = r._fld7371rref
    JOIN public._reference163 s ON s._idrref = c._fld685rref
    WHERE r._period >= DATE '2024-05-01' AND r._recordkind = 0
      AND CAST(s._description AS varchar(1000)) LIKE '%ИП%'
), legacy_month AS (
    SELECT date_trunc('month', _period)::date AS month_start, club_id, service_id,
           sum(revenue) AS revenue, count(DISTINCT client_id) AS legacy_quantity
    FROM ip GROUP BY 1, 2, 3
)
SELECT count(*) AS movement_rows, sum(revenue) AS revenue,
       count(*) FILTER (WHERE NOT _active) AS inactive_rows,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno))
           AS duplicate_technical_keys,
       sum(revenue) FILTER (WHERE _period >= DATE '2025-01-01' AND _period < DATE '2027-01-01')
           AS pbit_window_revenue,
       (SELECT sum(legacy_quantity) FROM legacy_month
         WHERE month_start >= DATE '2025-01-01' AND month_start < DATE '2027-01-01')
           AS pbit_window_monthly_distinct_clients
FROM ip;

-- SV-058: exact PZ branch from the PBIT, reduced to the technical event key.
-- The left join to VT is intentional here: it is the observed legacy logic.
WITH pz AS (
    SELECT i._recordertref, i._recorderrref, i._lineno
    FROM public._inforg7006 i
    JOIN public._reference141x1 client ON client._idrref = i._fld7008rref
    JOIN public._reference132 club ON club._idrref = i._fld7009rref
    JOIN public._document329 doc ON doc._idrref = i._fld7007_rrref
    JOIN public._reference225 employee ON employee._idrref = doc._fld4322rref
    JOIN public._enum448 state ON state._idrref = i._fld7013rref
    LEFT JOIN public._document329_vt4352 vt ON vt._document329_idrref = doc._idrref
    LEFT JOIN public._reference163 service ON service._idrref = i._fld7010rref
    WHERE i._period >= DATE '2024-01-01'
      AND (encode(i._fld7010rref, 'hex') = 'bcd000505688c8b011ee0a8ba155d4a1'
        OR encode(vt._fld4358rref, 'hex') = 'a0f1524d502e0d5d4c1dfeb9d5bbb3fe')
      AND state._enumorder NOT IN (2, 3)
)
SELECT count(*) AS pbit_rows,
       count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS source_events,
       count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS join_excess
FROM pz;

-- SV-059 uses the literal PBIT visit SQL extracted from
-- /Users/ilia/Downloads/Telegram Desktop/KPI фитнеса.pbit. The live result
-- and its document-key control are documented in server_validation_2026-08-05.md.
