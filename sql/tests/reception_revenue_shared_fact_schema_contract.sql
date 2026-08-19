-- Read-only acceptance after approved shared-fact scope migration.
-- Expected before a separately approved reception initial load: the shared
-- fact keeps all existing DPFU rows, the reception view exists and has 0 rows.
SELECT
    (SELECT count(*)
     FROM information_schema.columns
     WHERE table_schema = 'mart'
       AND table_name = 'ancillary_revenue_movement') = 21 AS columns_match,
    (SELECT count(*)
     FROM pg_constraint con
     JOIN pg_class rel ON rel.oid = con.conrelid
     JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'mart'
       AND rel.relname = 'ancillary_revenue_movement'
       AND con.contype IN ('p', 'c')) = 7 AS key_and_checks_match,
    (SELECT count(*)
     FROM pg_attribute a
     JOIN pg_class rel ON rel.oid = a.attrelid
     JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'mart'
       AND rel.relname = 'ancillary_revenue_movement'
       AND a.attnum > 0 AND NOT a.attisdropped AND a.attnotnull) = 10 AS not_null_match,
    (SELECT count(*)
     FROM mart.ancillary_revenue_movement
     WHERE revenue_scope <> 'dpfu'
        OR reception_category_key IS NOT NULL) = 0 AS dpfu_rows_preserved,
    to_regclass('mart.v_dpfu_ancillary_revenue') IS NOT NULL
        AND to_regclass('mart.v_reception_revenue') IS NOT NULL AS views_exist,
    (SELECT count(*) FROM mart.v_dpfu_ancillary_revenue)
        = (SELECT count(*) FROM mart.ancillary_revenue_movement) AS dpfu_view_preserves_rows,
    (SELECT count(*) FROM mart.v_reception_revenue) = 0 AS empty_before_reception_initial_load;
