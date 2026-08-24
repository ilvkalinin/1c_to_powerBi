-- Stage-3 target reconciliation for minimal date facts.
-- Execute inside the same target transaction after COPY.

-- NV-R01: transport completeness. Expected: passed = true.
SELECT $1::bigint AS expected_first_visit_rows,
       $2::bigint AS expected_guest_visit_rows,
       (SELECT count(*)::bigint FROM mart.new_first_visit) AS actual_first_visit_rows,
       (SELECT count(*)::bigint FROM mart.guest_visit_conversion) AS actual_guest_visit_rows,
       ($1::bigint = (SELECT count(*) FROM mart.new_first_visit)
        AND $2::bigint = (SELECT count(*) FROM mart.guest_visit_conversion)) AS passed;

-- NV-R02: logical keys. Expected: both values = 0.
SELECT (SELECT count(*)::bigint
        FROM (SELECT contract_id FROM mart.new_first_visit GROUP BY 1 HAVING count(*) > 1) AS q)
           AS duplicate_contract_keys,
       (SELECT count(*)::bigint
        FROM (SELECT client_id, guest_visit_date FROM mart.guest_visit_conversion
              GROUP BY 1, 2 HAVING count(*) > 1) AS q)
           AS duplicate_guest_client_date_keys;

-- NV-R03: required fields and outcome invariants. Expected: all values = 0.
SELECT (SELECT count(*)::bigint FROM mart.new_first_visit
        WHERE contract_id IS NULL OR btrim(contract_id) = '' OR first_visit_date IS NULL)
           AS invalid_first_visit_rows,
       (SELECT count(*)::bigint FROM mart.guest_visit_conversion
        WHERE client_id IS NULL OR btrim(client_id) = '' OR guest_visit_date IS NULL
           OR accuniq_same_day_flag IS NULL
           OR (purchase_activation_date IS NULL AND purchase_lag_days IS NOT NULL)
           OR (purchase_activation_date IS NOT NULL
               AND (purchase_lag_days NOT BETWEEN 0 AND 44
                    OR purchase_activation_date <> guest_visit_date + purchase_lag_days)))
           AS invalid_guest_visit_rows;

-- NV-R04: BR-003 horizon. Expected: both values = 0.
SELECT (SELECT count(*)::bigint FROM mart.new_first_visit
        WHERE first_visit_date < $3::date OR first_visit_date >= $4::date)
           AS first_visit_outside_horizon,
       (SELECT count(*)::bigint FROM mart.guest_visit_conversion
        WHERE guest_visit_date < $3::date OR guest_visit_date >= $4::date)
           AS guest_visit_outside_horizon;

-- NV-R05: minimal date-grain rule. Expected: all values = 0.
SELECT (SELECT count(*)::bigint FROM mart.new_first_visit
        WHERE first_visit_date IS NULL) AS first_visit_date_missing,
       (SELECT count(*)::bigint FROM mart.guest_visit_conversion
        WHERE client_code IS NULL) AS guest_rows_without_current_pbi_client_code,
       (SELECT count(*)::bigint FROM mart.guest_visit_conversion
        WHERE purchase_activation_date IS NOT NULL AND NOT accuniq_same_day_flag
          AND purchase_lag_days NOT BETWEEN 0 AND 44) AS impossible_outcome_rows;

-- NV-R06: access boundary. Expected: 0.
SELECT count(*)::bigint AS public_select_grants
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS a
WHERE n.nspname = 'mart'
  AND c.relname IN ('new_first_visit', 'guest_visit_conversion')
  AND a.grantee = 0
  AND a.privilege_type = 'SELECT';
