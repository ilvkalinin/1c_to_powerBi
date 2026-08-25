-- NM2-R01: target cardinality supplied by the independent source snapshot.
SELECT count(*)::bigint AS target_rows, $1::bigint AS expected_source_rows,
       count(*)::bigint - $1::bigint AS difference
FROM mart.newcomer_engagement_second_month;

-- NM2-R02: physical source identity is unique; legacy duplicate business pairs are preserved.
SELECT count(*) - count(DISTINCT source_row_id) AS duplicate_source_identity,
       count(*) - count(DISTINCT (contract_id, client_id, month_of_engagement)) AS duplicate_business_pairs
FROM mart.newcomer_engagement_second_month;

-- NM2-R03: mapped mandatory columns, range and bucket contract are valid.
SELECT count(*) FILTER (WHERE source_row_id IS NULL OR contract_id IS NULL OR client_id IS NULL
                          OR membership_start_date IS NULL OR month_of_engagement IS NULL
                          OR visit_bucket IS NULL OR intro_training_status IS NULL) AS mandatory_nulls,
       count(*) FILTER (WHERE second_month_visit_count < 0
                          OR visit_bucket <> CASE WHEN second_month_visit_count >= 4 THEN '4+' ELSE second_month_visit_count::text END) AS bucket_violations,
       count(*) FILTER (WHERE last_visit_date IS NOT NULL AND (last_visit_date < month_of_engagement
                          OR last_visit_date >= month_of_engagement + INTERVAL '1 month')) AS visit_interval_violations
FROM mart.newcomer_engagement_second_month;

-- NM2-R04: BR-003 date horizon and future-date boundary.
SELECT count(*) FILTER (WHERE month_of_engagement < $1::date OR month_of_engagement >= $2::date) AS outside_horizon,
       count(*) FILTER (WHERE last_visit_date > current_date) AS future_visits
FROM mart.newcomer_engagement_second_month;

-- NM2-R05: child packages retain the approved age category and sales-derived eligibility is accepted by source controls.
SELECT count(*) FILTER (WHERE source_row_id LIKE 'child:%' AND age_category <> 'Дети') AS child_not_kids,
       count(*) FILTER (WHERE source_row_id LIKE 'child:%') AS child_rows
FROM mart.newcomer_engagement_second_month;
