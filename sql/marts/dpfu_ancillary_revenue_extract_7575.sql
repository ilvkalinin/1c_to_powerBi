-- Source extract for mart.ancillary_revenue_movement, register AccumRg7575.
-- REVIEW ONLY. The runner binds $1 = horizon_start and $2 = horizon_end,
-- opens both branch extracts in one REPEATABLE READ, READ ONLY transaction,
-- and streams the explicit columns to VM-2. Do not execute this file on VM-2.

SELECT
    '7575'::text AS source_kind,
    encode(r._recorderrref, 'hex') AS recorder_id,
    r._lineno::integer AS line_no,
    r._period::date AS service_date,
    encode(r._fld7577rref, 'hex') AS club_id,
    CAST(c._code AS varchar(1000)) AS client_key,
    CAST(c._code AS varchar(1000)) AS client_code,
    encode(r._fld7582rref, 'hex') AS employee_id,
    CAST(e._description AS varchar(1000)) AS employee_name,
    encode(r._fld7579rref, 'hex') AS service_id,
    CAST(s._fld1761 AS varchar(1000)) AS service_name,
    encode(s._fld1733rref, 'hex') AS activity_id,
    CASE CAST(a._description AS varchar(1000))
        WHEN 'Тренажёрный зал' THEN 'Тренажёрный зал (Штат)'
        WHEN 'Тренажерный зал' THEN 'Тренажёрный зал (Штат)'
        ELSE CAST(a._description AS varchar(1000))
    END AS activity_name,
    encode(s._fld1803rref, 'hex') AS training_format_id,
    CASE CAST(f._description AS varchar(1000))
        WHEN 'Платный урок' THEN 'Групповое занятие'
        ELSE CAST(f._description AS varchar(1000))
    END AS training_format_name,
    CASE
        WHEN CAST(s._description AS varchar(1000)) ILIKE '%Аренда%'
         AND CAST(club._description AS varchar(1000)) NOT IN ('Пушкинский', 'Пушкинский VIP')
            THEN 'Аренда'
        ELSE 'Прочая услуга'
    END AS calculation_category,
    CASE
        WHEN c._fld1507 IS NULL THEN NULL
        WHEN extract(year FROM age(r._period::date, c._fld1507::date)) < 14 THEN 'Дети'
        WHEN extract(year FROM age(r._period::date, c._fld1507::date)) < 18 THEN 'Юниоры'
        ELSE 'Взрослые'
    END AS age_category,
    r._fld7585::numeric(15, 3) AS service_quantity,
    r._fld7586::numeric(15, 2) AS revenue_amount
FROM public._accumrg7575 r
JOIN public._reference163 s ON s._idrref = r._fld7579rref
JOIN public._reference70 a ON a._idrref = s._fld1733rref
JOIN public._reference132 club ON club._idrref = r._fld7577rref
JOIN public._reference141x1 c ON c._idrref = r._fld7576rref
LEFT JOIN public._reference225 e ON e._idrref = r._fld7582rref
LEFT JOIN public._reference248 f ON f._idrref = s._fld1803rref
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
