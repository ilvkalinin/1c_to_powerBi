-- REVIEW ONLY — execute only after an explicit rollback decision for this
-- package. Verify that both relations were created by this package and no
-- downstream consumer has been switched before execution.

BEGIN;
DROP TABLE mart.marketing_funnel_task_contract;
DROP TABLE mart.marketing_funnel_task;
COMMIT;
