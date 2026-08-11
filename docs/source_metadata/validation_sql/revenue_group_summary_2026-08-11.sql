-- Revenue-group summary server validation, executed 2026-08-11 in a
-- READ ONLY transaction against gymdb. No source object is changed.

-- GK-V01: the technical movement key must be physically unique and non-NULL
-- in every source register. Expected: all four rows have three NOT NULL
-- columns of types bytea, bytea, numeric(9,0), and a matching unique index.
WITH key_columns(attname) AS (
    VALUES ('_recordertref'), ('_recorderrref'), ('_lineno')
)
SELECT r.relname,
       bool_and(a.attnotnull) FILTER (WHERE k.attname IS NOT NULL) AS key_columns_not_null,
       string_agg(
           a.attname || ':' || format_type(a.atttypid, a.atttypmod),
           ', ' ORDER BY a.attnum
       ) FILTER (WHERE k.attname IS NOT NULL) AS key_column_types,
       EXISTS (
           SELECT 1
           FROM pg_index i
           WHERE i.indrelid = r.oid
             AND i.indisunique
             AND pg_get_indexdef(i.indexrelid) ILIKE '%_recordertref%'
             AND pg_get_indexdef(i.indexrelid) ILIKE '%_recorderrref%'
             AND pg_get_indexdef(i.indexrelid) ILIKE '%_lineno%'
       ) AS unique_technical_index
FROM pg_class r
JOIN pg_namespace n ON n.oid = r.relnamespace
JOIN pg_attribute a ON a.attrelid = r.oid
                    AND a.attnum > 0
                    AND NOT a.attisdropped
LEFT JOIN key_columns k ON k.attname = a.attname
WHERE n.nspname = 'public'
  AND r.relname IN ('_accumrg7370', '_accumrg7575', '_accumrg7646', '_accumrg7739')
GROUP BY r.relname, r.oid
ORDER BY r.relname;

-- GK-V02: the physical club dimension may be used as a stable technical key.
-- Expected: a non-NULL unique bytea ID and no duplicate/nonblank descriptions.
SELECT count(*) AS club_rows,
       count(DISTINCT _idrref) AS distinct_club_ids,
       count(*) FILTER (WHERE _idrref IS NULL) AS null_club_ids,
       count(*) FILTER (WHERE _description IS NULL OR btrim(_description::text) = '')
           AS null_or_blank_descriptions,
       count(*) - count(DISTINCT _description) AS duplicate_descriptions,
       pg_typeof(max(_idrref))::text AS club_id_type
FROM public._reference132;
