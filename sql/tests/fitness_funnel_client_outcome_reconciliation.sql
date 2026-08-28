-- Future target reconciliation. $1 expected row count, $2 inclusive date,
-- $3 exclusive date; execute before target commit.
SELECT 'FF-O-R01'::text AS control_id, $1::bigint AS expected_value,
       count(*)::bigint AS actual_value,
       CASE WHEN count(*)=$1::bigint THEN 'PASS' ELSE 'FAIL' END AS status
FROM mart.fitness_funnel_client_outcome
UNION ALL
SELECT 'FF-O-R02',$1::bigint,count(DISTINCT outcome_source_key)::bigint,
       CASE WHEN count(DISTINCT outcome_source_key)=$1::bigint THEN 'PASS' ELSE 'FAIL' END
FROM mart.fitness_funnel_client_outcome
UNION ALL
SELECT 'FF-O-R03',0::bigint,count(*) FILTER (WHERE client_key IS NULL OR outcome_date IS NULL OR club_id IS NULL OR service_id IS NULL OR employee_id IS NULL OR outcome_count<>1)::bigint,
       CASE WHEN count(*) FILTER (WHERE client_key IS NULL OR outcome_date IS NULL OR club_id IS NULL OR service_id IS NULL OR employee_id IS NULL OR outcome_count<>1)=0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fitness_funnel_client_outcome
UNION ALL
SELECT 'FF-O-R04',0::bigint,count(*) FILTER (WHERE outcome_date<$2::date OR outcome_date>=$3::date)::bigint,
       CASE WHEN count(*) FILTER (WHERE outcome_date<$2::date OR outcome_date>=$3::date)=0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fitness_funnel_client_outcome;
