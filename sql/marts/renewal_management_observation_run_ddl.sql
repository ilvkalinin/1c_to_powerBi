BEGIN;

CREATE TABLE mart.renewal_management_observation_run (
    run_id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at          timestamptz NOT NULL,
    finished_at         timestamptz,
    status              text NOT NULL,
    parent_exit_code    integer,
    observation_exit_code integer,
    baseline_rows       bigint NOT NULL DEFAULT 0,
    changed_rows        bigint NOT NULL DEFAULT 0,
    removed_rows        bigint NOT NULL DEFAULT 0,
    CONSTRAINT renewal_management_observation_run_status_ck
        CHECK (status IN ('RUNNING', 'SUCCEEDED', 'FAILED_PARENT', 'FAILED_OBSERVATION')),
    CONSTRAINT renewal_management_observation_run_counts_ck
        CHECK (baseline_rows >= 0 AND changed_rows >= 0 AND removed_rows >= 0),
    CONSTRAINT renewal_management_observation_run_finished_ck
        CHECK ((status = 'RUNNING' AND finished_at IS NULL)
               OR (status <> 'RUNNING' AND finished_at IS NOT NULL))
);

COMMENT ON TABLE mart.renewal_management_observation_run IS
    'PII-free operational journal for the parent-refresh then observation-append chain.';

REVOKE ALL ON mart.renewal_management_observation_run FROM PUBLIC;

COMMIT;
