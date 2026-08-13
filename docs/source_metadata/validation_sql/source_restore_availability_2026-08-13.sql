-- SV-090: source-restoration availability check.
-- Execute only against gymdb with gymdb_readonly in a READ ONLY transaction.
-- No query returns PII or raw business identifiers.
--
-- Expected before execution:
-- 1. gymdb and gymdb_readonly are active, and transaction_read_only = on.
-- 2. _document294, _document275 and _document298_vt3596 each exist in public
--    as an ordinary table (relkind = 'r') with at least one physical column.
-- 3. _document275 has rows for the previously observed Document275 recorder
--    type in _accumrg7575, or records zero explicitly as a source-snapshot
--    discrepancy; the check does not expose recorder IDs.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000';

SELECT current_database() AS database_name,
       current_user AS current_role,
       current_setting('transaction_read_only') AS transaction_read_only;

WITH expected(relname) AS (
    VALUES ('_document294'), ('_document275'), ('_document298_vt3596')
), relations AS (
    SELECT e.relname,
           c.relkind,
           COALESCE((
               SELECT count(*)::bigint
               FROM pg_attribute a
               WHERE a.attrelid = c.oid
                 AND a.attnum > 0
                 AND NOT a.attisdropped
           ), 0) AS physical_column_count
    FROM expected e
    LEFT JOIN pg_class c
      ON c.relname = e.relname
     AND c.relnamespace = 'public'::regnamespace
)
SELECT relname,
       COALESCE(relkind::text, 'MISSING') AS relation_kind,
       physical_column_count
FROM relations
ORDER BY relname;

SELECT count(*)::bigint AS accumrg7575_document275_rows,
       count(d._idrref)::bigint AS matched_document275_rows
FROM _accumrg7575 a
LEFT JOIN _document275 d
  ON d._idrref = a._recorderrref
WHERE a._recordertref = '\\x00000113'::bytea;

COMMIT;
