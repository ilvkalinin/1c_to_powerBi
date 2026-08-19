-- Read-only schema acceptance after approved DDL.
-- Expected one row: the table has four columns, two table constraints and no
-- rows before a separately approved initial load.
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
       AND rel.relname = 'revenue_group_summary_daily') = 2 AS constraints_match,
    (SELECT count(*)
     FROM mart.revenue_group_summary_daily) = 0 AS empty_before_initial_load;
