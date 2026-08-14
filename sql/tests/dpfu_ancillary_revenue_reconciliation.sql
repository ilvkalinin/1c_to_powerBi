-- Read-only reconciliation for mart.ancillary_revenue_movement.
-- The runner binds $1 = horizon_start and $2 = horizon_end to both source
-- controls. Run the controls in the same REPEATABLE READ, READ ONLY source
-- snapshot as the two detailed extract files; record both result rows in
-- _ancillary_revenue_movement_expected before VM-2 replacement.
--
-- Expected result before a run: exactly one aggregate row per source branch.
-- Expected result after a successful run: the target query returns the same
-- two rows as the captured source controls, with zero duplicate keys and zero
-- contract violations. Tolerance for rows, quantity and revenue: exactly zero.

-- Source control: 7575. Environment: VM-1 / gymdb / read-only snapshot.
SELECT
    '7575'::text AS source_kind,
    count(*)::bigint AS movement_rows,
    sum(r._fld7585)::numeric(18, 3) AS service_quantity,
    sum(r._fld7586)::numeric(18, 2) AS revenue_amount
FROM public._accumrg7575 r
JOIN public._reference163 s ON s._idrref = r._fld7579rref
JOIN public._reference70 a ON a._idrref = s._fld1733rref
WHERE r._period >= $1::date
  AND r._period < $2::date
  AND r._fld7586 <> 0
  AND s._fld1795rref = '\x9f007d77d46892dc47058346701d3bb6'::bytea
  AND a._fld843rref NOT IN (
      '\x9e10e872e49a551b4968a66b95c28905'::bytea,
      '\xac626c95655c992a471b27ca8f8812cd'::bytea
  )
  AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
  AND CAST(a._description AS varchar(1000)) IN (
      'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
      'Детский клуб', 'Водные программы', 'Групповые программы',
      'Тренажёрный зал', 'Тренажерный зал'
  );

-- Source control: 7646. Environment: VM-1 / gymdb / read-only snapshot.
SELECT
    '7646'::text AS source_kind,
    count(*)::bigint AS movement_rows,
    sum(r._fld7657)::numeric(18, 3) AS service_quantity,
    sum(r._fld7659)::numeric(18, 2) AS revenue_amount
FROM public._accumrg7646 r
JOIN public._reference163 s ON s._idrref = r._fld7649rref
JOIN public._reference70 a ON a._idrref = s._fld1733rref
WHERE r._period >= $1::date
  AND r._period < $2::date
  AND r._fld7659 <> 0
  AND s._fld1795rref NOT IN (
      '\x9f007d77d46892dc47058346701d3bb6'::bytea,
      '\x89de5e634e304b1a44efac5ab7088373'::bytea,
      '\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea
  )
  AND a._fld843rref NOT IN (
      '\x9e10e872e49a551b4968a66b95c28905'::bytea,
      '\xac626c95655c992a471b27ca8f8812cd'::bytea
  )
  AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
  AND CAST(a._description AS varchar(1000)) IN (
      'Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
      'Детский клуб', 'Водные программы', 'Групповые программы',
      'Тренажёрный зал', 'Тренажерный зал'
  );

-- Target controls. Environment: VM-2 / fitness_dwh / read-only transaction.
-- Compare each result to the two captured source-control rows above.
SELECT
    source_kind,
    count(*)::bigint AS movement_rows,
    sum(service_quantity)::numeric(18, 3) AS service_quantity,
    sum(revenue_amount)::numeric(18, 2) AS revenue_amount,
    count(*) - count(DISTINCT (source_kind, recorder_id, line_no)) AS duplicate_keys,
    count(*) FILTER (
        WHERE client_key IS NULL OR client_key <> client_code
           OR service_date IS NULL OR service_date < $1::date OR service_date >= $2::date
           OR calculation_category NOT IN ('Прочая услуга', 'Аренда')
           OR age_category NOT IN ('Дети', 'Юниоры', 'Взрослые')
    ) AS contract_violations
FROM mart.ancillary_revenue_movement
GROUP BY source_kind
ORDER BY source_kind;

-- Refresh deletion check: after every run the fact contains no row outside the
-- currently captured BR-003 horizon. Expected result: 0.
SELECT count(*) AS rows_outside_horizon
FROM mart.ancillary_revenue_movement
WHERE service_date < $1::date OR service_date >= $2::date;
