-- NE-R01 — target cardinality supplied by the current source snapshot.
SELECT count(*)::bigint AS target_rows, $1::bigint AS expected_source_rows,
       count(*)::bigint = $1::bigint AS passed
FROM mart.newcomer_engagement_milestone;

-- NE-R02 — physical target key is unique.
SELECT count(*) - count(DISTINCT (contract_id, client_id, checkpoint_day)) AS duplicate_keys
FROM mart.newcomer_engagement_milestone;

-- NE-R03 — invariant and allowed-value violations are absent.
SELECT count(*) FILTER (WHERE checkpoint_day NOT IN (7,14,21,28,30)) AS bad_checkpoint_day,
       count(*) FILTER (WHERE checkpoint_date <> membership_start_date + checkpoint_day - 1) AS bad_checkpoint_date,
       count(*) FILTER (WHERE visit_count_to_checkpoint < 0) AS bad_visit_count,
       count(*) FILTER (WHERE visit_bucket NOT IN ('0','1','2','3','4+')) AS bad_visit_bucket
FROM mart.newcomer_engagement_milestone;

-- NE-R04 — returned child-package start date is excluded (ERF sales/returns sample).
SELECT count(*) FILTER (WHERE membership_start_date = DATE '2025-11-22') AS returned_start_rows,
       count(*) FILTER (WHERE membership_start_date = DATE '2026-03-21') AS nonreturned_start_rows
FROM mart.newcomer_engagement_milestone
WHERE contract_code = 'ФЮ00151485' AND client_code = 'И00058515';

-- NE-R05 — repeated valid child-package dates use the user-approved maximum.
SELECT count(*) FILTER (WHERE membership_start_date = DATE '2026-06-19') AS earlier_start_rows,
       count(*) FILTER (WHERE membership_start_date = DATE '2026-07-21') AS maximum_start_rows
FROM mart.newcomer_engagement_milestone
WHERE contract_code = 'ФЮ00159691' AND client_code = '001305732';

-- NE-R06 — no checkpoint lies outside the approved BR-003 horizon.
SELECT count(*) FILTER (WHERE checkpoint_date < DATE '2025-01-01') AS before_horizon,
       count(*) FILTER (WHERE checkpoint_date >= DATE '2027-01-01') AS after_horizon,
       count(*) FILTER (WHERE checkpoint_day NOT IN (7,14,21,28,30)) AS invalid_checkpoint_set
FROM mart.newcomer_engagement_milestone;
