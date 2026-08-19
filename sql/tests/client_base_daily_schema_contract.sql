-- Read-only schema acceptance after approved DDL.
-- Expected: seven columns, one unique key, four business checks, five NOT NULL
-- columns and no rows before a separately approved initial load.
SELECT
    (SELECT count(*)
     FROM information_schema.columns
     WHERE table_schema = 'mart' AND table_name = 'client_base_daily') = 7 AS columns_match,
    (SELECT count(*)
     FROM pg_constraint con
     JOIN pg_class rel ON rel.oid = con.conrelid
     JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'mart'
       AND rel.relname = 'client_base_daily'
       AND con.contype IN ('u', 'c')) = 5 AS key_and_checks_match,
    (SELECT count(*)
     FROM pg_attribute a
     JOIN pg_class rel ON rel.oid = a.attrelid
     JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'mart'
       AND rel.relname = 'client_base_daily'
       AND a.attnum > 0 AND NOT a.attisdropped AND a.attnotnull) = 5 AS not_null_match,
    (SELECT count(*) FROM mart.client_base_daily) = 0 AS empty_before_initial_load;
