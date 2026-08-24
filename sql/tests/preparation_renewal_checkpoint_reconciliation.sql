-- Stage-3 reconciliation for mart.preparation_renewal_checkpoint.
-- Execute inside the target transaction after all bounded COPY batches.
-- $1 rows; $2 visits; $3 frozen points; $4 below-target points;
-- $5/$6 are the BR-003 checkpoint-date horizon.

-- PR-R01: independent legacy-M source controls. Expected: passed = true.
SELECT $1::bigint AS expected_rows,
       $2::bigint AS expected_visit_count,
       $3::bigint AS expected_frozen_points,
       $4::bigint AS expected_below_target_points,
       (SELECT count(*)::bigint FROM mart.preparation_renewal_checkpoint) AS actual_rows,
       (SELECT coalesce(sum(visit_count_to_checkpoint), 0)::bigint
        FROM mart.preparation_renewal_checkpoint) AS actual_visit_count,
       (SELECT count(*) FILTER (WHERE frozen_at_checkpoint_flag)::bigint
        FROM mart.preparation_renewal_checkpoint) AS actual_frozen_points,
       (SELECT count(*) FILTER (WHERE below_target_flag)::bigint
        FROM mart.preparation_renewal_checkpoint) AS actual_below_target_points,
       ($1::bigint = (SELECT count(*) FROM mart.preparation_renewal_checkpoint)
        AND $2::bigint = (SELECT coalesce(sum(visit_count_to_checkpoint), 0)
                           FROM mart.preparation_renewal_checkpoint)
        AND $3::bigint = (SELECT count(*) FILTER (WHERE frozen_at_checkpoint_flag)
                           FROM mart.preparation_renewal_checkpoint)
        AND $4::bigint = (SELECT count(*) FILTER (WHERE below_target_flag)
                           FROM mart.preparation_renewal_checkpoint)) AS passed;

-- PR-R02: logical contract × checkpoint key. Expected: 0.
SELECT count(*)::bigint AS duplicate_grain_groups
FROM (
    SELECT contract_id, checkpoint_day
    FROM mart.preparation_renewal_checkpoint
    GROUP BY 1, 2
    HAVING count(*) > 1
) AS duplicate_groups;

-- PR-R03: physical contract and current-rule derived values. Expected: all 0.
SELECT count(*) FILTER (
           WHERE contract_id IS NULL OR btrim(contract_id) = ''
              OR contract_code IS NULL OR client_id IS NULL
              OR access_club_id IS NULL OR access_club_name IS NULL
              OR membership_start_date IS NULL OR membership_end_date IS NULL
              OR checkpoint_date IS NULL OR visit_count_to_checkpoint < 0
       )::bigint AS invalid_required_rows,
       count(*) FILTER (WHERE checkpoint_day NOT IN (7, 14, 21, 28, 30))::bigint
           AS invalid_checkpoint_days,
       count(*) FILTER (WHERE visit_bucket <> CASE WHEN visit_count_to_checkpoint >= 4 THEN '4+'
                                                    ELSE visit_count_to_checkpoint::text END)::bigint
           AS invalid_visit_buckets,
       count(*) FILTER (WHERE target_visit_count <> CASE checkpoint_day
           WHEN 7 THEN 1 WHEN 14 THEN 2 WHEN 21 THEN 3 WHEN 28 THEN 4 WHEN 30 THEN 4 END)::bigint
           AS invalid_targets,
       count(*) FILTER (WHERE below_target_flag <> (visit_count_to_checkpoint < target_visit_count))::bigint
           AS invalid_below_target_flags,
       count(*) FILTER (WHERE age_group IS NOT NULL
                          AND age_group NOT IN ('Дети', 'Юниоры', 'Взрослые'))::bigint AS invalid_age_groups,
       count(*) FILTER (WHERE membership_tenure NOT IN ('New', 'Renew', 'Ex'))::bigint AS invalid_tenures
FROM mart.preparation_renewal_checkpoint;

-- PR-R04: DAX checkpoint-date formula and BR-003 horizon. Expected: both 0.
SELECT count(*) FILTER (WHERE checkpoint_date <> membership_end_date - 121 + checkpoint_day)::bigint
           AS wrong_checkpoint_dates,
       count(*) FILTER (WHERE checkpoint_date < $5::date OR checkpoint_date >= $6::date)::bigint
           AS out_of_horizon_rows
FROM mart.preparation_renewal_checkpoint;

-- PR-R05: one-to-five point set per contract. Expected: 0.
SELECT count(*)::bigint AS invalid_contract_point_sets
FROM (
    SELECT contract_id
    FROM mart.preparation_renewal_checkpoint
    GROUP BY contract_id
    HAVING bool_or(checkpoint_day NOT IN (7, 14, 21, 28, 30))
        OR count(DISTINCT checkpoint_day) <> count(*)
) AS invalid_sets;

-- PR-R06: access boundary. Expected: 0.
SELECT count(*)::bigint AS public_select_grants
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS a
WHERE n.nspname = 'mart'
  AND c.relname = 'preparation_renewal_checkpoint'
  AND a.grantee = 0
  AND a.privilege_type = 'SELECT';
