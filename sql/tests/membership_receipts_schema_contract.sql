-- Read-only schema acceptance after approved DDL.
-- Expected single row: both tables exist, are empty, and match the contract.
WITH expected_objects(table_name, expected_columns, expected_constraints) AS (
    VALUES
        ('membership_receipt_movement'::text, 43::bigint, 15::bigint),
        ('membership_contract_kpi_unit'::text, 30::bigint, 13::bigint)
), actual AS (
    SELECT e.table_name,
           (SELECT count(*)
            FROM information_schema.columns c
            WHERE c.table_schema = 'mart' AND c.table_name = e.table_name) AS actual_columns,
           (SELECT count(*)
            FROM pg_constraint con
            JOIN pg_class rel ON rel.oid = con.conrelid
            JOIN pg_namespace ns ON ns.oid = rel.relnamespace
            WHERE ns.nspname = 'mart' AND rel.relname = e.table_name) AS actual_constraints,
           CASE e.table_name
               WHEN 'membership_receipt_movement' THEN
                   (SELECT count(*) FROM mart.membership_receipt_movement)
               WHEN 'membership_contract_kpi_unit' THEN
                   (SELECT count(*) FROM mart.membership_contract_kpi_unit)
           END AS row_count
    FROM expected_objects e
)
SELECT a.table_name,
       a.actual_columns = e.expected_columns AS columns_match,
       a.actual_constraints = e.expected_constraints AS constraints_match,
       a.row_count = 0 AS empty_before_initial_load
FROM actual a
JOIN expected_objects e USING (table_name)
ORDER BY a.table_name;
