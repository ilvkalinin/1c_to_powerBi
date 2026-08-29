-- Stage-3 reconciliation for mart.renewal_management_contract.
-- $1 rows; $2 distinct contracts; $3/$4 end-date bounds; $5 purchase price;
-- $6 visits; $7 renewed; $8 renewed by month close; $9 renewed current; $10 paid renewed.

-- RM-R01: independent source aggregate controls. Expected: passed = true.
SELECT $1::bigint AS expected_rows,$2::bigint AS expected_distinct_contracts,
       $3::date AS expected_min_end_date,$4::date AS expected_max_end_date,$5::numeric AS expected_purchase_price,
       $6::bigint AS expected_visit_count,$7::bigint AS expected_renewed_count,
       $8::bigint AS expected_renewed_by_month_close_count,$9::bigint AS expected_renewed_current_count,
       $10::bigint AS expected_paid_renewed_count,
       (SELECT count(*) FROM mart.renewal_management_contract) AS actual_rows,
       (SELECT count(DISTINCT expiring_contract_id) FROM mart.renewal_management_contract) AS actual_distinct_contracts,
       (SELECT min(membership_end_date) FROM mart.renewal_management_contract) AS actual_min_end_date,
       (SELECT max(membership_end_date) FROM mart.renewal_management_contract) AS actual_max_end_date,
       (SELECT coalesce(sum(purchase_price),0) FROM mart.renewal_management_contract) AS actual_purchase_price,
       (SELECT coalesce(sum(visit_count),0) FROM mart.renewal_management_contract) AS actual_visit_count,
       (SELECT count(*) FILTER (WHERE next_contract_id IS NOT NULL) FROM mart.renewal_management_contract) AS actual_renewed_count,
       (SELECT count(*) FILTER (WHERE renewed_by_month_close_flag) FROM mart.renewal_management_contract) AS actual_renewed_by_month_close_count,
       (SELECT count(*) FILTER (WHERE renewed_current_flag) FROM mart.renewal_management_contract) AS actual_renewed_current_count,
       (SELECT count(*) FILTER (WHERE next_contract_id IS NOT NULL AND renewal_type='Платное продление') FROM mart.renewal_management_contract) AS actual_paid_renewed_count,
       ($1::bigint=(SELECT count(*) FROM mart.renewal_management_contract)
        AND $2::bigint=(SELECT count(DISTINCT expiring_contract_id) FROM mart.renewal_management_contract)
        AND $3::date=(SELECT min(membership_end_date) FROM mart.renewal_management_contract)
        AND $4::date=(SELECT max(membership_end_date) FROM mart.renewal_management_contract)
        AND $5::numeric=(SELECT coalesce(sum(purchase_price),0) FROM mart.renewal_management_contract)
        AND $6::bigint=(SELECT coalesce(sum(visit_count),0) FROM mart.renewal_management_contract)
        AND $7::bigint=(SELECT count(*) FILTER (WHERE next_contract_id IS NOT NULL) FROM mart.renewal_management_contract)
        AND $8::bigint=(SELECT count(*) FILTER (WHERE renewed_by_month_close_flag) FROM mart.renewal_management_contract)
        AND $9::bigint=(SELECT count(*) FILTER (WHERE renewed_current_flag) FROM mart.renewal_management_contract)
        AND $10::bigint=(SELECT count(*) FILTER (WHERE next_contract_id IS NOT NULL AND renewal_type='Платное продление') FROM mart.renewal_management_contract)) AS passed;

-- RM-R02: grain, required values and contract horizon. Expected: all 0.
SELECT count(*) FILTER (WHERE expiring_contract_id IS NULL OR btrim(expiring_contract_id)=''
                              OR expiring_contract_code IS NULL OR client_id IS NULL OR client_code IS NULL
                              OR membership_start_date IS NULL OR membership_end_date IS NULL
                              OR access_club_id IS NULL OR membership_term_days<30 OR visit_count<0)::bigint AS invalid_required_rows,
       count(*) FILTER (WHERE membership_end_date<membership_start_date
                              OR contract_end_month<>date_trunc('month',membership_end_date)::date)::bigint AS invalid_dates,
       count(*) FILTER (WHERE membership_end_date<$3::date OR membership_end_date>$4::date)::bigint AS out_of_horizon_rows
FROM mart.renewal_management_contract;

-- RM-R03: persisted renewal calculations. Expected: all 0.
SELECT count(*) FILTER (WHERE renewed_by_month_close_flag<>coalesce(renewal_activation_date<=contract_end_month+interval '1 month',false))::bigint AS invalid_month_close_flag,
       count(*) FILTER (WHERE renewed_current_flag<>coalesce(renewal_activation_date<=current_date,false))::bigint AS invalid_current_flag,
       count(*) FILTER (WHERE (next_contract_id IS NULL)<>(renewal_activation_date IS NULL))::bigint AS invalid_next_presence,
       count(*) FILTER (WHERE renewal_type='Не продлен' AND next_contract_id IS NOT NULL)::bigint AS invalid_not_renewed_type,
       count(*) FILTER (WHERE renewal_type<>'Не продлен' AND next_contract_id IS NULL)::bigint AS invalid_renewed_type
FROM mart.renewal_management_contract;

-- RM-R04: return and non-additive formulas. Expected: all 0.
SELECT count(*) FILTER (WHERE renewal_lead_lag_days IS DISTINCT FROM renewal_activation_date-membership_end_date)::bigint AS invalid_lead_lag,
       count(*) FILTER (WHERE return_days IS DISTINCT FROM CASE WHEN renewal_activation_date>membership_end_date THEN renewal_activation_date-membership_end_date END)::bigint AS invalid_return_days,
       count(*) FILTER (WHERE usage_rate IS DISTINCT FROM visit_count::numeric/nullif(membership_term_days,0))::bigint AS invalid_usage_rate,
       count(*) FILTER (WHERE average_monthly_visits IS DISTINCT FROM visit_count::numeric/nullif((12*(extract(year FROM membership_end_date)-extract(year FROM membership_start_date))+extract(month FROM membership_end_date)-extract(month FROM membership_start_date)+1),0))::bigint AS invalid_monthly_visits
FROM mart.renewal_management_contract;

-- RM-R05: domains and PUBLIC boundary. Expected: all 0.
SELECT count(*) FILTER (WHERE renewal_type NOT IN ('Не продлен','Платное продление','Бесплатное длинное продление','Бесплатное короткое продление'))::bigint AS invalid_renewal_type,
       count(*) FILTER (WHERE return_bucket IS NOT NULL AND return_bucket NOT IN ('До окончания','0–30','31–60','61–90','91–180','181+'))::bigint AS invalid_return_bucket,
       (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
        WHERE n.nspname='mart' AND c.relname='renewal_management_contract'
          AND a.grantee=0 AND a.privilege_type='SELECT')::bigint AS public_select_grants
FROM mart.renewal_management_contract;
