-- Read-only schema acceptance after approved DDL.
-- Expected one row: the table has four columns, one primary-key and one check
-- constraint, every column NOT NULL, and no rows before an approved load.
SELECT
    (SELECT count(*)
     FROM information_schema.columns
     WHERE table_schema = 'mart'
       AND table_name = 'revenue_group_summary_daily') = 4 AS columns_match,
    (SELECT count(*)
     FROM pg_constraint con
     JOIN pg_class rel ON rel.oid = con.conrelid
     JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'mart'
       AND rel.relname = 'revenue_group_summary_daily'
       AND con.contype IN ('p', 'c')) = 2 AS key_and_check_match,
    (SELECT count(*)
     FROM pg_attribute a
     JOIN pg_class rel ON rel.oid = a.attrelid
     JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'mart'
       AND rel.relname = 'revenue_group_summary_daily'
       AND a.attnum > 0
       AND NOT a.attisdropped
       AND a.attnotnull) = 4 AS not_null_match,
    (SELECT count(*)
     FROM mart.revenue_group_summary_daily) = 0 AS empty_before_initial_load;
