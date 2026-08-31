-- OPS-R01: journal carries no malformed lifecycle/count data. Expected all 0.
SELECT
    count(*) FILTER (WHERE status NOT IN ('RUNNING', 'SUCCEEDED', 'FAILED_PARENT', 'FAILED_OBSERVATION'))::bigint AS invalid_status_rows,
    count(*) FILTER (WHERE baseline_rows < 0 OR changed_rows < 0 OR removed_rows < 0)::bigint AS invalid_count_rows,
    count(*) FILTER (WHERE (status = 'RUNNING') <> (finished_at IS NULL))::bigint AS invalid_finished_state_rows,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
     WHERE n.nspname = 'mart' AND c.relname = 'renewal_management_observation_run'
       AND a.grantee = 0 AND a.privilege_type = 'SELECT')::bigint AS public_select_grants
FROM mart.renewal_management_observation_run;
