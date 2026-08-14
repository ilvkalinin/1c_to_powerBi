-- S3-ADMISSION-001: aggregate-only check for the DPFU client key.
-- Run on gymdb as gymdb_readonly inside BEGIN READ ONLY. Do not return codes,
-- raw client IDs, or other personal data.
WITH qualified_clients AS (
    -- Use the two branches and filters from SV-054 unchanged; retain only
    -- the source client reference from each selected movement.
    SELECT r._fld7576rref AS client_id
    FROM public._accumrg7575 r
    JOIN public._reference163 s ON s._idrref = r._fld7579rref
    JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= DATE '2024-01-01' AND r._period < DATE '2027-01-01'
      AND r._fld7586 <> 0
      AND s._fld1795rref = '\\x9f007d77d46892dc47058346701d3bb6'::bytea
      AND a._fld843rref NOT IN ('\\x9e10e872e49a551b4968a66b95c28905'::bytea, '\\xac626c95655c992a471b27ca8f8812cd'::bytea)
      AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(a._description AS varchar(1000)) IN ('Игровой зал', 'Восстановительный фитнес', 'Боевые искусства', 'Детский клуб', 'Водные программы', 'Групповые программы', 'Тренажёрный зал', 'Тренажерный зал')
    UNION ALL
    SELECT r._fld7648rref
    FROM public._accumrg7646 r
    JOIN public._reference163 s ON s._idrref = r._fld7649rref
    JOIN public._reference70 a ON a._idrref = s._fld1733rref
    WHERE r._period >= DATE '2024-01-01' AND r._period < DATE '2027-01-01'
      AND r._fld7659 <> 0
      AND s._fld1795rref NOT IN ('\\x9f007d77d46892dc47058346701d3bb6'::bytea, '\\x89de5e634e304b1a44efac5ab7088373'::bytea, '\\xbaad3eba9d9fe9b441d2a1a897435c33'::bytea)
      AND a._fld843rref NOT IN ('\\x9e10e872e49a551b4968a66b95c28905'::bytea, '\\xac626c95655c992a471b27ca8f8812cd'::bytea)
      AND CAST(s._description AS varchar(1000)) <> 'посещение клуба'
      AND CAST(a._description AS varchar(1000)) IN ('Игровой зал', 'Восстановительный фитнес', 'Боевые искусства', 'Детский клуб', 'Водные программы', 'Групповые программы', 'Тренажёрный зал', 'Тренажерный зал')
),
scoped_clients AS (
    SELECT DISTINCT client_id FROM qualified_clients
),
scoped_codes AS (
    SELECT CAST(c._code AS varchar(1000)) AS client_code
    FROM scoped_clients q
    JOIN public._reference141x1 c ON c._idrref = q.client_id
)
SELECT
    COUNT(*) AS distinct_client_ids,
    COUNT(*) FILTER (WHERE client_code IS NULL) AS null_code_ids,
    COUNT(*) FILTER (WHERE btrim(COALESCE(client_code, '')) = '') AS blank_code_ids,
    COUNT(*) - COUNT(DISTINCT client_code) AS duplicate_code_excess_ids
FROM scoped_codes;

-- S3-ADMISSION-002: the proposed technical key needs no RecorderTRef on the
-- qualified DPFU scope. Use the SV-054 CTE, retaining source_kind,
-- _recorderrref and _lineno; expected both duplicate counts = 0.
-- SELECT
--     COUNT(*) - COUNT(DISTINCT (source_kind, _recorderrref, _lineno))
--         AS duplicates_without_recorder_type,
--     COUNT(*) - COUNT(DISTINCT (source_kind, _recordertref, _recorderrref, _lineno))
--         AS duplicates_with_recorder_type
-- FROM qualified_dpfu;

-- S3-ADMISSION-003: physical types verified through information_schema.columns.
-- Expected: _lineno numeric(9,0); 7575 quantity/revenue numeric(15,2);
-- 7646 quantity numeric(15,3) and revenue numeric(15,2).
